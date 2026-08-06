require "test_helper"

class RunArchiverTest < ActiveSupport::TestCase
  include OpenDataTestHelper

  setup { setup_open_data_env }
  teardown { teardown_open_data_env }

  test "archives originals, standard.csv and meta.json into a dated folder" do
    project = create_project("alpha")
    FileUtils.mkdir_p(project + "original-data")
    File.write(project + "original-data/original.csv", "raw\n")
    FileUtils.mkdir_p(project + "generated-data")
    File.write(project + "generated-data/standard.csv", default_csv)

    run = data_sources(:alpha).download_runs.create!(status: :running, triggered_by: :manual,
      started_at: Time.current)
    now = Time.utc(2026, 8, 6, 12, 30, 45)
    dir = RunArchiver.new(run, now: now).call

    assert_equal (OpenData.downloads_root + "alpha/2026-08-06_123045").to_s, dir.to_s
    assert File.file?(dir + "original/original.csv")
    assert_equal default_csv, File.read(dir + "standard.csv")

    meta = JSON.parse(File.read(dir + "meta.json"))
    assert_equal "alpha", meta.dig("data_source", "directory")
    assert_equal "Alpha Co-ops", meta.dig("data_source", "name")
    assert_equal "manual", meta.dig("run", "triggered_by")
    assert_equal run.id, meta.dig("run", "id")
  end

  test "copes with a project that has no original-data" do
    project = create_project("alpha")
    FileUtils.mkdir_p(project + "generated-data")
    File.write(project + "generated-data/standard.csv", default_csv)

    run = data_sources(:alpha).download_runs.create!(status: :running, triggered_by: :manual)
    dir = RunArchiver.new(run).call
    assert File.file?(dir + "standard.csv")
    assert_not File.directory?(dir + "original")
  end
end
