require "test_helper"

class DiskUsageJobTest < ActiveJob::TestCase
  include OpenDataTestHelper

  setup { setup_open_data_env }
  teardown { teardown_open_data_env }

  test "measures the downloads and builds folders" do
    FileUtils.mkdir_p(OpenData.downloads_root + "alpha/2026-10-05_060000")
    File.write(OpenData.downloads_root + "alpha/2026-10-05_060000/standard.csv", "x" * 50_000)
    FileUtils.mkdir_p(OpenData.builds_root + "cwm/2026-10-05_071530")
    File.write(OpenData.builds_root + "cwm/2026-10-05_071530/unified.csv", "y" * 120_000)

    DiskUsageJob.perform_now
    usage = DiskUsage.latest
    assert_operator usage.downloads_bytes, :>=, 50_000
    assert_operator usage.builds_bytes, :>=, 120_000
    assert_in_delta Time.current, usage.measured_at, 5
  end

  test "counts a missing folder as empty and keeps one row" do
    2.times { DiskUsageJob.perform_now }
    assert_equal 1, DiskUsage.count
    assert_equal 0, DiskUsage.latest.downloads_bytes
  end

  test "a finished build measures again" do
    build = projects(:cwm).project_builds.create!(status: :queued)
    assert_enqueued_with(job: DiskUsageJob) { ProjectBuildJob.perform_now(build) }
    assert build.reload.failed?, "no source data, so the build itself fails quickly"
  end
end
