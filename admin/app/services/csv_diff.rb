require "csv"

# Compares two standard.csv files keyed on the Identifier column and reports
# added, removed and changed rows.
class CsvDiff
  KEY = "Identifier".freeze
  MAX_DETAIL_LINES = 500

  Result = Struct.new(:added, :removed, :changed, :summary, :detail, keyword_init: true)

  def self.call(old_path, new_path)
    new(old_path, new_path).call
  end

  def initialize(old_path, new_path)
    @old_path = old_path
    @new_path = new_path
  end

  def call
    new_rows = index(@new_path)
    if @old_path.nil?
      return Result.new(added: new_rows.size, removed: 0, changed: 0,
        summary: "First download: #{new_rows.size} rows.",
        detail: "First download: no previous version to compare against. #{new_rows.size} rows.\n")
    end

    old_rows = index(@old_path)
    added = new_rows.keys - old_rows.keys
    removed = old_rows.keys - new_rows.keys
    changed = (new_rows.keys & old_rows.keys).select { |k| new_rows[k] != old_rows[k] }

    Result.new(
      added: added.size, removed: removed.size, changed: changed.size,
      summary: "#{added.size} added, #{removed.size} removed, #{changed.size} changed " \
               "(#{new_rows.size} rows, was #{old_rows.size}).",
      detail: detail(old_rows, new_rows, added, removed, changed)
    )
  end

  private

  def index(path)
    rows = {}
    CSV.foreach(path, headers: true) do |row|
      key = row[KEY] || row.fields.first
      rows[key] = row.to_h
    end
    rows
  end

  def detail(old_rows, new_rows, added, removed, changed)
    lines = []
    added.each { |k| lines << "+ #{k}: #{new_rows[k].values_at('Name').first}" }
    removed.each { |k| lines << "- #{k}: #{old_rows[k].values_at('Name').first}" }
    changed.each do |k|
      fields = new_rows[k].select { |f, v| old_rows[k][f] != v }.keys
      lines << "~ #{k}: #{fields.join(', ')}"
    end
    truncated = lines.size > MAX_DETAIL_LINES
    lines = lines.first(MAX_DETAIL_LINES)
    lines << "... truncated, #{added.size + removed.size + changed.size} differences in total" if truncated
    lines << "No differences." if lines.empty?
    lines.join("\n") + "\n"
  end
end
