# One run of a project's unified CSV build (see ProjectBuilder).
class ProjectBuild < ApplicationRecord
  belongs_to :project

  enum :status, { queued: 0, running: 1, succeeded: 2, failed: 4 }

  # As DownloadRun: a build whose job died stays queued/running forever and
  # blocks the project, so it is failed once it has been idle this long.
  STALE_AFTER = 6.hours

  def self.reap_stale!
    where(status: %i[queued running])
      .where(updated_at: ...STALE_AFTER.ago)
      .find_each do |build|
        build.append_log("Marked failed: no activity for #{STALE_AFTER.inspect} (job lost, likely an app restart).\n")
        build.update!(status: :failed, finished_at: Time.current)
      end
  end

  def duration
    return nil unless started_at && finished_at
    finished_at - started_at
  end

  def csv_path
    return nil if archive_path.blank?
    path = File.join(archive_path, "unified.csv")
    File.file?(path) ? path : nil
  end

  def append_log(text)
    self.log = [ log, text ].compact.join
  end
end
