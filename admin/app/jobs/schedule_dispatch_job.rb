# Runs every minute (config/recurring.yml) and enqueues a DownloadRun for
# each enabled source whose cron schedule has come due.
class ScheduleDispatchJob < ApplicationJob
  queue_as :default

  def perform
    DownloadRun.reap_stale!
    ProjectBuild.reap_stale!
    ProjectDataset.reap_stale!
    DataSource.enabled.find_each do |source|
      next unless source.due? && !source.running?
      run = source.download_runs.create!(status: :queued, triggered_by: :scheduled)
      DataSourceRunJob.perform_later(run)
    end
  end
end
