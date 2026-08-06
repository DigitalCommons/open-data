# Archives one run's downloaded and converted files into a dated folder:
#
#   <downloads_root>/<source-directory>/<YYYY-MM-DD_HHMMSS>/
#     meta.json          source and run details
#     original/...       contents of the project's original-data/
#     standard.csv       the converted output
class RunArchiver
  attr_reader :run, :source

  def initialize(run, now: Time.current)
    @run = run
    @source = run.data_source
    @now = now
  end

  def call
    base = OpenData.downloads_root + source.directory + @now.strftime("%Y-%m-%d_%H%M%S")
    dir = base
    suffix = 1
    dir = Pathname.new("#{base}-#{suffix += 1}") while dir.exist?
    FileUtils.mkdir_p(dir)

    original_data = source.project_dir + "original-data"
    if original_data.directory?
      FileUtils.mkdir_p(dir + "original")
      original_data.children.select(&:file?).each { |f| FileUtils.cp(f, dir + "original") }
    end

    standard_csv = source.project_dir + "generated-data/standard.csv"
    FileUtils.cp(standard_csv, dir) if standard_csv.file?

    File.write(dir + "meta.json", JSON.pretty_generate(meta))
    dir
  end

  private

  def meta
    {
      data_source: source.slice(:name, :directory, :description, :download_url, :kind, :schedule),
      run: {
        id: run.id,
        triggered_by: run.triggered_by,
        uploaded_filename: run.uploaded_filename,
        started_at: run.started_at,
        archived_at: @now
      }
    }
  end
end
