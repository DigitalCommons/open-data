require "csv"

# Builds a project's unified CSV from the latest converted standard.csv of
# each source in its unify settings (cleaned by UnifiedCsv::Cleaner, then
# merged by UnifiedCsv::Unifier) and archives it:
#
#   <builds_root>/<project-key>/<YYYY-MM-DD_HHMMSS>/
#     meta.json     project and the download run behind each input
#     cleaned/      <code>.cleaned.csv per table and clean-csv-data.tsv,
#                   the cleaner's log in data-pipelines' format
#     unified.csv   the cleaned sources merged by UnifiedCsv::Unifier, with
#                   Created At / Updated At per row (RowStamps)
#     diff.txt      changes since the previous successful build
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
    previous_csv = previous_build&.csv_path
    stats = UnifiedCsv::Unifier.new(settings, cleaned.to_h).unify(dir + "unified.csv")
    stamp_rows(dir + "unified.csv", previous_csv, cleaned)
    record_diff(previous_csv, dir)
    File.write(dir + "meta.json", JSON.pretty_generate(meta(inputs)))
    build.row_count = stats[:rows]
    build.merged_count = stats[:merged]
    build.append_log("Unified: #{stats[:rows]} rows, #{stats[:merged]} merged from #{inputs.size} sources.\n")
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

  def previous_build
    project.project_builds.succeeded.where.not(id: build.id).order(created_at: :desc).first
  end

  # A merged row lists its source records as "code=Identifier;..."
  MEMBERS = ->(row) { row["Identifiers"].to_s.split(";").map { |pair| pair.sub("=", "/") } }

  # Created At / Updated At per merged row: carried over from the previous
  # build (through member records when the merged Identifier changed), or,
  # where the previous build has no dates, taken from the member source
  # rows' own dates.
  def stamp_rows(path, previous_csv, cleaned)
    result = RowStamps.apply(path.to_s, previous_path: previous_csv, at: build.started_at,
      members: MEMBERS, seed: source_row_dates(cleaned))
    build.append_log("Row dates: #{result[:added]} new, #{result[:changed]} changed, #{result[:unchanged]} unchanged.\n")
  end

  # "code/Identifier" => [Created At, Updated At] from the cleaned sources.
  def source_row_dates(cleaned)
    cleaned.each_with_object({}) do |(code, path), dates|
      CSV.foreach(path, headers: true, encoding: "UTF-8") do |row|
        next if row["Identifier"].blank? || row[RowStamps::CREATED].blank?
        dates["#{code}/#{row['Identifier']}"] = [ row[RowStamps::CREATED], row[RowStamps::UPDATED] ]
      end
    end
  end

  def record_diff(previous_csv, dir)
    diff = CsvDiff.call(previous_csv, (dir + "unified.csv").to_s)
    File.write(dir + "diff.txt", diff.detail)
    build.assign_attributes(rows_added: diff.added, rows_removed: diff.removed,
      rows_changed: diff.changed, diff_summary: diff.summary)
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
