require "test_helper"

class DataSourceTest < ActiveSupport::TestCase
  include OpenDataTestHelper

  setup { setup_open_data_env }
  teardown { teardown_open_data_env }

  test "directory must be unique and a plain name" do
    dupe = DataSource.new(directory: "alpha", name: "Dupe")
    assert_not dupe.valid?

    traversal = DataSource.new(directory: "../evil", name: "Evil")
    assert_not traversal.valid?
    assert_includes traversal.errors[:directory], "must be a plain directory name"
  end

  test "schedule must be a valid cron expression" do
    source = data_sources(:alpha)
    source.schedule = "not a cron"
    assert_not source.valid?

    source.schedule = "0 4 * * *"
    assert source.valid?
  end

  test "enabling an auto source requires a schedule" do
    source = data_sources(:alpha)
    source.schedule = nil
    assert_not source.valid?

    source.enabled = false
    assert source.valid?
  end

  test "manual source can be enabled without schedule" do
    source = data_sources(:beta)
    source.enabled = true
    assert source.valid?
  end

  test "due? when never run and cron has fired" do
    source = data_sources(:alpha)
    source.download_runs.destroy_all
    assert source.due?
  end

  test "not due when a run started since the last cron fire" do
    source = data_sources(:alpha)
    source.download_runs.create!(status: :succeeded, triggered_by: :scheduled)
    assert_not source.due?
  end

  test "due again once the next cron fire passes" do
    source = data_sources(:alpha)
    source.download_runs.destroy_all
    source.download_runs.create!(status: :succeeded, triggered_by: :scheduled, created_at: 25.minutes.ago)
    assert source.due?
  end

  test "not due when disabled or manual or unscheduled" do
    source = data_sources(:alpha)
    source.download_runs.destroy_all

    source.enabled = false
    assert_not source.due?

    source.enabled = true
    source.kind = :manual
    assert_not source.due?

    source.kind = :auto
    source.schedule = nil
    assert_not source.due?
  end

  test "overdue? when the last download predates a full missed cycle" do
    source = data_sources(:alpha)
    source.download_runs.destroy_all
    assert source.overdue?, "never-downloaded scheduled source is overdue"

    source.download_runs.create!(status: :succeeded, triggered_by: :scheduled,
      started_at: 2.hours.ago, finished_at: 2.hours.ago, created_at: 2.hours.ago)
    assert source.overdue?

    source.download_runs.create!(status: :succeeded, triggered_by: :scheduled,
      started_at: 1.minute.ago, finished_at: 1.minute.ago)
    assert_not source.reload.overdue?
  end

  test "running? reflects queued or running runs" do
    source = data_sources(:alpha)
    assert_not source.running?
    source.download_runs.create!(status: :queued, triggered_by: :manual)
    assert source.running?
  end

  test "last_downloaded_at ignores failed runs" do
    source = data_sources(:alpha)
    assert_in_delta 2.hours.ago.to_f, source.last_downloaded_at.to_f, 60
  end

  test "sync_from_repo! registers new projects without clobbering existing ones" do
    create_project("gamma")
    File.write(OpenData.root + "gamma/downloader", "#!/bin/sh\n")
    create_project("delta")
    (OpenData.root + "not-a-project").mkpath

    original_name = data_sources(:alpha).name
    DataSource.sync_from_repo!

    gamma = DataSource.find_by!(directory: "gamma")
    assert gamma.auto?
    assert_not gamma.enabled?

    delta = DataSource.find_by!(directory: "delta")
    assert delta.manual?

    assert_nil DataSource.find_by(directory: "not-a-project")
    assert_equal original_name, data_sources(:alpha).reload.name
  end

  test "legacy live sources are seeded enabled on the 10 minute schedule" do
    create_project("ica")
    File.write(OpenData.root + "ica/downloader", "#!/bin/sh\n")
    DataSource.sync_from_repo!

    ica = DataSource.find_by!(directory: "ica")
    assert ica.enabled?
    assert_equal "*/10 * * * *", ica.schedule
  end
end
