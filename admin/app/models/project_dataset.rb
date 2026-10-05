# One MykoMaps dataset built from a project's unified CSV and map config
# (see ProjectDatasetBuilder).
class ProjectDataset < ApplicationRecord
  belongs_to :project
  belongs_to :project_build

  enum :status, { queued: 0, running: 1, succeeded: 2, failed: 4 }

  # As ProjectBuild: a dataset build whose job died is failed once idle this long.
  STALE_AFTER = 6.hours

  def self.reap_stale!
    where(status: %i[queued running]).where(updated_at: ...STALE_AFTER.ago).find_each do |dataset|
      dataset.append_log("Marked failed: no activity for #{STALE_AFTER.inspect} (job lost, likely an app restart).\n")
      dataset.update!(status: :failed, finished_at: Time.current)
    end
  end

  def zip_path
    return nil if archive_path.blank?
    path = File.join(archive_path, "dataset.zip")
    File.file?(path) ? path : nil
  end

  # e.g. 20261005-080001-cwm-dataset.zip
  def download_filename
    DownloadFilename.for(started_at || created_at, project.key, "dataset.zip")
  end

  def append_log(text)
    self.log = [ log, text ].compact.join
  end
end
