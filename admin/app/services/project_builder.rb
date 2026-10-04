require "csv"

# Builds a project's unified CSV from the latest converted standard.csv of
# each source in its unify settings, then archives it:
#
#   <builds_root>/<project-key>/<YYYY-MM-DD_HHMMSS>/
#     meta.json     project and the download run behind each input
#     cleaned/      <code>.cleaned.csv per table and clean-csv-data.tsv,
#                   the cleaner's log in data-pipelines' format
#     unified.csv   the output
class ProjectBuilder
  attr_reader :build, :project, :settings

  def initialize(build, settings: build.project.unify_settings, now: Time.current)
    @build = build
    @project = build.project
    @settings = settings
    @now = now
  end

  def call
    build.update!(status: :running, started_at: Time.current)

    inputs = settings.tables.map { |table| input_for(table) }
    missing = inputs.select { |input| input[:run].nil? }
    if missing.any?
      missing.each { |input| build.append_log("#{input[:table].source} has no converted standard.csv yet.\n") }
      return finish(:failed)
    end

    dir = archive_dir
    cleaned = clean(inputs, dir + "cleaned")
    headers, rows = combine(cleaned)
    write_csv(dir + "unified.csv", headers, rows)
    File.write(dir + "meta.json", JSON.pretty_generate(meta(inputs)))
    build.row_count = rows.size
    build.append_log("Wrote #{rows.size} rows from #{inputs.size} sources.\n")
    finish(:succeeded)
  rescue StandardError => e
    build.append_log("#{e.class}: #{e.message}\n")
    finish(:failed)
  end

  private

  def input_for(table)
    source = DataSource.find_by(directory: table.source)
    { table: table, source: source, run: source&.last_succeeded_run }
  end

  # Cleans each input into dir; returns [code, cleaned path] pairs.
  def clean(inputs, dir)
    FileUtils.mkdir_p(dir)
    log = []
    cleaned = inputs.map do |input|
      table = input[:table]
      path = dir + "#{table.code}.cleaned.csv"
      log << { dataset_id: table.code, type: "info", message: "load", url: input[:run].standard_csv_path }
      count = UnifiedCsv::Cleaner.new(code: table.code, row_filter: table.row_filter, log: log)
        .clean(input[:run].standard_csv_path, path)
      build.append_log("#{table.code}: #{count} rows from #{table.source}\n")
      [ table.code, path ]
    end
    write_clean_log(dir + "clean-csv-data.tsv", log)
    cleaned
  end

  # The data-pipelines TSV log; tabs and newlines in values are %-encoded.
  def write_clean_log(path, entries)
    escape = ->(value) { value.to_s.gsub(/[\t\n\r]/) { |char| format("%%%02X", char.ord) } }
    File.open(path, "w") do |file|
      file.puts %w[ datasetId id type message url domain ].join("\t")
      entries.each do |entry|
        file.puts entry.values_at(:dataset_id, :id, :type, :message, :url, :domain).map(&escape).join("\t")
      end
    end
  end

  # Every cleaned row; headers are the union of the inputs' headers in
  # first-seen order.
  def combine(cleaned)
    headers = []
    rows = []
    cleaned.each do |_code, path|
      csv = CSV.read(path, headers: true)
      headers |= csv.headers
      csv.each { |row| rows << row.to_h }
    end
    [ headers, rows ]
  end

  def write_csv(path, headers, rows)
    CSV.open(path, "w", quote_empty: false) do |csv|
      csv << headers
      rows.each { |row| csv << row.values_at(*headers) }
    end
  end

  def archive_dir
    dir = OpenData.builds_root + project.key + @now.strftime("%Y-%m-%d_%H%M%S")
    dir = Pathname.new("#{dir}-#{build.id}") if dir.exist?
    FileUtils.mkdir_p(dir)
    build.archive_path = dir.to_s
    dir
  end

  def meta(inputs)
    {
      project: project.key,
      build_id: build.id,
      built_at: @now.iso8601,
      inputs: inputs.map do |input|
        { code: input[:table].code, source: input[:table].source, download_run_id: input[:run].id,
          standard_csv: input[:run].standard_csv_path }
      end
    }
  end

  def finish(status)
    build.update!(status: status, finished_at: Time.current)
    build
  end
end
