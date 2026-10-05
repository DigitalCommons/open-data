# One run of a project's unified CSV build (see ProjectBuilder).
class ProjectBuild < ApplicationRecord
  belongs_to :project
  has_many :project_datasets, dependent: :destroy

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
    path_in_archive("unified.csv")
  end

  def diff_path
    path_in_archive("diff.txt")
  end

  # Number of sources the build read, from its archived meta.json.
  def input_count
    path = path_in_archive("meta.json")
    path && JSON.parse(File.read(path)).fetch("inputs", []).size
  end

  # e.g. 20261005-071530-cwm-unified.csv
  def download_filename(file)
    DownloadFilename.for(started_at || created_at, project.key, file)
  end

  def append_log(text)
    self.log = [ log, text ].compact.join
  end

  private

  def path_in_archive(filename)
    return nil if archive_path.blank?
    path = File.join(archive_path, filename)
    File.file?(path) ? path : nil
  end
end
