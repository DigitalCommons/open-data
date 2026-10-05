require "csv"

class RowStamps
  # Dates the rows of a source's latest download from its archived history:
  # replays every successful download's standard.csv in order through
  # RowStamps, then writes the result over the latest archive's
  # standard.csv, which later runs compare against. A download imported
  # with prod-2-data/import.rb is dated by the original file's modified
  # time recorded in its meta.json; others by the run's start time.
  class Backfill
    def initialize(source)
      @source = source
    end

    # :stamped, :already_stamped or :no_downloads
    def call
      runs = @source.download_runs.succeeded.order(:created_at).select(&:standard_csv_path)
      return :no_downloads if runs.empty?
      latest = runs.last.standard_csv_path
      return :already_stamped if (CSV.open(latest, &:readline) & COLUMNS).any?

      Dir.mktmpdir do |dir|
        previous = nil
        runs.each_with_index do |run, index|
          copy = File.join(dir, "#{index}.csv")
          FileUtils.cp(run.standard_csv_path, copy)
          RowStamps.apply(copy, previous_path: previous, at: downloaded_at(run))
          previous = copy
        end
        FileUtils.cp(previous, latest)
      end
      :stamped
    end

    private

    def downloaded_at(run)
      meta = File.join(run.archive_path, "meta.json")
      modified = File.file?(meta) && JSON.parse(File.read(meta))["standard_csv_modified_at"]
      modified ? Time.iso8601(modified) : run.started_at
    end
  end
end
