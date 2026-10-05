require "csv"

class DownloadRun < ApplicationRecord
  belongs_to :data_source

  enum :status, { queued: 0, running: 1, succeeded: 2, no_changes: 3, failed: 4 }
  enum :triggered_by, { scheduled: 0, manual: 1, upload: 2 }

  scope :completed, -> { where(status: %i[succeeded no_changes]) }

  # A run whose job died ungracefully (app killed mid-run) stays queued/running
  # forever and blocks its source via DataSource#running?. The runner saves the
  # run after every command, so updated_at is a coarse heartbeat.
  STALE_AFTER = 6.hours

  def self.reap_stale!
    where(status: %i[queued running])
      .where(updated_at: ...STALE_AFTER.ago)
      .find_each do |run|
        run.append_log("Marked failed: no activity for #{STALE_AFTER.inspect} (job lost, likely an app restart).\n")
        run.update!(status: :failed, finished_at: Time.current)
      end
  end

  def duration
    return nil unless started_at && finished_at
    finished_at - started_at
  end

  def standard_csv_path
    path_in_archive("standard.csv")
  end

  def diff_path
    path_in_archive("diff.txt")
  end

  # e.g. 20261005-060012-workers-coop-standard.csv
  def download_filename(file)
    DownloadFilename.for(started_at || created_at, data_source.directory, file)
  end

  # Rows in the archived standard.csv; counted once for runs recorded
  # before row_count was stored.
  def archived_row_count
    return row_count if row_count
    path = standard_csv_path or return nil
    count = CSV.foreach(path, headers: true).count
    update_column(:row_count, count)
    count
  end

  def append_log(text)
    self.log = [ log, text ].compact.join
  end

  def changes?
    [ rows_added, rows_removed, rows_changed ].compact.sum.positive?
  end

  private

  def path_in_archive(filename)
    return nil if archive_path.blank?
    path = File.join(archive_path, filename)
    File.file?(path) ? path : nil
  end
end
