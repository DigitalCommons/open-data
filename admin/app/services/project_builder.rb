require "csv"

# Builds a project's unified CSV from the latest converted standard.csv of
# each source in its unify settings, then archives it:
#
#   <builds_root>/<project-key>/<YYYY-MM-DD_HHMMSS>/
#     meta.json     project and the download run behind each input
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

    headers, rows = combine(inputs)
    archive(inputs) { |dir| write_csv(dir + "unified.csv", headers, rows) }
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

  # Every input row with a Dataset column naming its table; headers are the
  # union of the inputs' headers in first-seen order.
  def combine(inputs)
    headers = []
    rows = []
    inputs.each do |input|
      csv = CSV.read(input[:run].standard_csv_path, headers: true)
      headers |= csv.headers
      csv.each { |row| rows << row.to_h.merge("Dataset" => input[:table].code) }
    end
    [ headers | [ "Dataset" ], rows ]
  end

  def write_csv(path, headers, rows)
    CSV.open(path, "w") do |csv|
      csv << headers
      rows.each { |row| csv << row.values_at(*headers) }
    end
  end

  def archive(inputs)
    dir = OpenData.builds_root + project.key + @now.strftime("%Y-%m-%d_%H%M%S")
    dir = Pathname.new("#{dir}-#{build.id}") if dir.exist?
    FileUtils.mkdir_p(dir)
    yield dir
    File.write(dir + "meta.json", JSON.pretty_generate(meta(inputs)))
    build.archive_path = dir.to_s
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
