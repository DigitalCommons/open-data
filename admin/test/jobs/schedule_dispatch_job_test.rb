require "test_helper"

class ScheduleDispatchJobTest < ActiveJob::TestCase
  setup do
    @source = data_sources(:alpha)
    @source.download_runs.destroy_all
  end

  test "enqueues a run for a due source" do
    assert_difference -> { @source.download_runs.scheduled.count } do
      assert_enqueued_with(job: DataSourceRunJob) { ScheduleDispatchJob.perform_now }
    end
    assert @source.download_runs.reload.last.queued?
  end

  test "skips sources that are not due" do
    @source.download_runs.create!(status: :succeeded, triggered_by: :scheduled)
    assert_no_difference -> { DownloadRun.count } do
      ScheduleDispatchJob.perform_now
    end
  end

  test "skips sources with a run in progress" do
    @source.download_runs.create!(status: :running, triggered_by: :manual, created_at: 1.hour.ago)
    assert_no_difference -> { DownloadRun.count } do
      ScheduleDispatchJob.perform_now
    end
  end

  test "skips disabled and manual sources" do
    @source.update!(enabled: false)
    assert_no_difference -> { DownloadRun.count } do
      ScheduleDispatchJob.perform_now
    end
  end
end
