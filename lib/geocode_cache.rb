require "csv"
require "fileutils"

# A geocode cache keyed on the query string, stored as a CSV with columns
# query,lat,lng,geocodedAddress so it can be committed. The layout matches
# the data-pipelines caches, so those files can be used unchanged.
class GeocodeCache
  HEADERS = %w[query lat lng geocodedAddress].freeze

  Entry = Struct.new(:lat, :lng, :geocoded_address)

  def initialize(path)
    @path = path
    @entries = {}
    load if File.exist?(path)
  end

  def [](query)
    @entries[query]
  end

  def []=(query, entry)
    @entries[query] = entry
  end

  def size
    @entries.size
  end

  # Writes to a temporary file then renames, so a failed run never leaves a
  # truncated cache. No trailing newline, matching data-pipelines.
  def save
    FileUtils.mkdir_p(File.dirname(@path))
    text = CSV.generate do |csv|
      csv << HEADERS
      @entries.each do |query, entry|
        csv << [query, entry.lat, entry.lng, entry.geocoded_address]
      end
    end
    temp = "#{@path}.tmp"
    File.write(temp, text.chomp)
    File.rename(temp, @path)
  end

  private

  def load
    CSV.foreach(@path, headers: true) do |row|
      next if row["query"].to_s.empty?

      @entries[row["query"]] = Entry.new(row["lat"], row["lng"], row["geocodedAddress"])
    end
  end
end
