class DownloadRun < ApplicationRecord
  belongs_to :data_source

  enum :status, { queued: 0, running: 1, succeeded: 2, no_changes: 3, failed: 4 }
  enum :triggered_by, { scheduled: 0, manual: 1, upload: 2 }

  scope :completed, -> { where(status: %i[succeeded no_changes]) }

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
