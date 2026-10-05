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

  test "sync_from_repo! registers new source directories without clobbering existing ones" do
    create_source_dir("gamma")
    File.write(OpenData.root + "gamma/downloader", "#!/bin/sh\n")
    create_source_dir("delta")
    (OpenData.root + "not-a-source").mkpath

    original_name = data_sources(:alpha).name
    DataSource.sync_from_repo!

    gamma = DataSource.find_by!(directory: "gamma")
    assert gamma.auto?
    assert_not gamma.enabled?

    delta = DataSource.find_by!(directory: "delta")
    assert delta.manual?

    assert_nil DataSource.find_by(directory: "not-a-source")
    assert_equal original_name, data_sources(:alpha).reload.name
  end

  test "sync applies curated details on create and fills blanks on existing records" do
    create_source_dir("gamma")
    create_source_dir("alpha")
    details = {
      "gamma" => { "description" => "Gamma origin and processing.", "download_url" => "https://gamma.example.com/data.csv" },
      "alpha" => { "description" => "Should not clobber", "download_url" => "https://alpha.example.com/new" }
    }

    alpha = data_sources(:alpha)
    alpha.update!(download_url: nil)

    DataSource.sync_from_repo!(details: details)

    gamma = DataSource.find_by!(directory: "gamma")
    assert_equal "Gamma origin and processing.", gamma.description
    assert_equal "https://gamma.example.com/data.csv", gamma.download_url

    alpha.reload
    assert_equal "A scheduled source", alpha.description, "edited description must survive"
    assert_equal "https://alpha.example.com/new", alpha.download_url, "blank url should be filled"
  end

  test "curated details file parses and covers only known directories" do
    details = DataSource.source_details
    assert_kind_of Hash, details
    details.each do |dir, info|
      assert_match(/\A[\w.-]+\z/, dir)
      assert info["description"].present?, "#{dir} needs a description"
    end
  end

  test "legacy live sources are seeded enabled on the daily 6am UK time schedule" do
    create_source_dir("ica")
    File.write(OpenData.root + "ica/downloader", "#!/bin/sh\n")
    DataSource.sync_from_repo!

    ica = DataSource.find_by!(directory: "ica")
    assert ica.enabled?
    assert_equal "0 6 * * * Europe/London", ica.schedule
  end

  test "the default schedule fires at 6am UK time, summer and winter" do
    source = data_sources(:alpha)
    source.update!(schedule: DataSource::DEFAULT_SCHEDULE)
    source.download_runs.delete_all
    source.download_runs.create!(status: :succeeded, triggered_by: :scheduled, created_at: Time.utc(2026, 6, 30, 12))

    assert_not source.due?(Time.utc(2026, 7, 1, 4, 59)), "04:59 UTC is 05:59 BST"
    assert source.due?(Time.utc(2026, 7, 1, 5, 1)), "05:01 UTC is 06:01 BST"

    source.download_runs.create!(status: :succeeded, triggered_by: :scheduled, created_at: Time.utc(2026, 12, 1, 12))
    assert_not source.due?(Time.utc(2026, 12, 2, 5, 59))
    assert source.due?(Time.utc(2026, 12, 2, 6, 1)), "GMT in winter"
  end

  test "row_id_note comes from the curated details file" do
    assert_match(/CiviCRM contact ID/, DataSource.new(directory: "ica").row_id_note)
    assert_nil DataSource.new(directory: "not-a-source").row_id_note
  end

  test "every source directory in the repo documents its row ID" do
    details = DataSource.source_details
    missing = Dir.glob(Rails.root.join("../*/converter")).map { |path| File.basename(File.dirname(path)) }
      .reject { |dir| details.dig(dir, "row_id").present? }
    assert_empty missing
  end
end
