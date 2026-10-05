require "csv"
require "digest"

# Adds "Created At" and "Updated At" to a CSV by comparing it with the
# previous version of the same data, matching rows on Identifier:
#
# - a new Identifier gets both dates set to `at`
# - a row whose other columns changed keeps Created At, Updated At = `at`
# - an unchanged row keeps both dates
#
# Rows with a blank or repeated Identifier cannot be matched and are dated
# `at`. With `members`, a row not found by Identifier takes the earliest
# Created At of the previous rows whose Identifiers it lists (for merged
# rows whose Identifier changed), and Updated At = `at`. Where the previous
# version has no dates for a row, `seed` (member Identifier => [created,
# updated]) dates it by its members' earliest Created At and latest
# Updated At. The file is rewritten in place with the two columns last.
class RowStamps
  KEY = "Identifier".freeze
  CREATED = "Created At".freeze
  UPDATED = "Updated At".freeze
  COLUMNS = [ CREATED, UPDATED ].freeze

  def self.apply(path, previous_path:, at:, members: nil, seed: nil)
    new(path, previous_path, at, members, seed).apply
  end

  def self.strip(row)
    row.except(*COLUMNS)
  end

  # Identifies a row's content, other than its dates, independent of
  # column order.
  def self.fingerprint(values)
    Digest::SHA1.digest(strip(values).sort.to_s)
  end

  def initialize(path, previous_path, at, members, seed)
    @path = path
    @members = members
    @seed = seed
    @created_by_member = {}
    @previous = previous_path ? index(previous_path) : {}
    @at = at.utc.iso8601
  end

  def apply
    counts = Hash.new(0)
    headers = nil
    CSV.foreach(@path, headers: true, encoding: "UTF-8") do |row|
      headers ||= row.headers - COLUMNS + COLUMNS
      counts[row[KEY]] += 1
    end
    headers ||= CSV.open(@path, encoding: "UTF-8", &:readline).to_a - COLUMNS + COLUMNS
    result = { added: 0, changed: 0, unchanged: 0, untracked: 0 }

    stamped_path = "#{@path}.stamping"
    CSV.open(stamped_path, "w", quote_empty: false) do |out|
      out << headers
      CSV.foreach(@path, headers: true, encoding: "UTF-8") do |row|
        values = row.to_h
        id = values[KEY]
        created, updated, outcome = stamp(id, values, trackable: id.present? && counts[id] == 1)
        result[outcome] += 1
        out << self.class.strip(values).merge(CREATED => created, UPDATED => updated).values_at(*headers)
      end
    end
    File.rename(stamped_path, @path)
    result
  end

  private

  def stamp(id, values, trackable:)
    return [ @at, @at, :untracked ] unless trackable

    if (old = @previous[id])
      dates = old[:created] ? [ old[:created], old[:updated] || old[:created] ] : (seeded_dates(values) || [ @at, @at ])
      return [ *dates, :unchanged ] if old[:fingerprint] == self.class.fingerprint(values)
      return [ dates.first, @at, :changed ]
    end

    inherited = inherited_created(values)
    return [ inherited, @at, :changed ] if inherited

    seeded = seeded_dates(values)
    seeded ? [ *seeded, :added ] : [ @at, @at, :added ]
  end

  def inherited_created(values)
    return nil unless @members
    @members.call(values).filter_map { |member| @created_by_member[member] }.min
  end

  def seeded_dates(values)
    return nil unless @seed && @members
    dates = @members.call(values).filter_map { |member| @seed[member] }
    created = dates.filter_map(&:first).min
    updated = dates.filter_map(&:last).max
    created && [ created, updated || created ]
  end

  # Previous rows by Identifier (content fingerprint and dates); with
  # `members`, also the earliest Created At of each member Identifier.
  def index(path)
    rows = {}
    CSV.foreach(path, headers: true, encoding: "UTF-8") do |row|
      values = row.to_h
      next if values[KEY].blank?
      created = values[CREATED].presence
      rows[values[KEY]] = { fingerprint: self.class.fingerprint(values), created: created, updated: values[UPDATED].presence }
      next unless @members && created
      @members.call(values).each do |member|
        @created_by_member[member] = [ @created_by_member[member], created ].compact.min
      end
    end
    rows
  end
end
