class DataSourceRunJob < ApplicationJob
  queue_as :default

  # The running? checks in the controllers and ScheduleDispatchJob are
  # check-then-act; two runs of one source can still be enqueued in the same
  # instant. Serialise execution per source so they never share project_dir.
  # (Solid Queue only; the semaphore expires after `duration` as a leak guard.)
  limits_concurrency key: ->(download_run) { download_run.data_source_id }, duration: 4.hours

  def perform(download_run)
    DataSourceRunner.new(download_run).call
  end
end
