require "test_helper"
require "zip"

class ProjectDatasetBuilderTest < ActiveSupport::TestCase
  include OpenDataTestHelper

  setup do
    setup_open_data_env
    @unified_dir = Dir.mktmpdir("unified")
    File.write(File.join(@unified_dir, "unified.csv"), file_fixture("dataset-cli/dummy.csv").read)
    @unified = projects(:cwm).project_builds.create!(status: :succeeded, started_at: Time.current, archive_path: @unified_dir)
    @map_dir = Pathname.new(Dir.mktmpdir("map"))
    File.write(@map_dir + "base.json", { "languages" => [ "fr" ], "ui" => { "directory_panel_field" => "activity" } }.to_json)
    FileUtils.mkdir_p(@map_dir + "cwm/assets/markers")
    overlay = JSON.parse(file_fixture("dataset-cli/config.json").read)
    File.write(@map_dir + "cwm/config.json", overlay.to_json)
    File.write(@map_dir + "cwm/about.md", "About the dummy map.\n")
    File.write(@map_dir + "cwm/assets/markers/a.png", "png")
  end

  teardown do
    teardown_open_data_env
    FileUtils.remove_entry(@unified_dir)
    FileUtils.remove_entry(@map_dir)
  end

  def build!
    dataset = projects(:cwm).project_datasets.create!(project_build: @unified, status: :queued)
    ProjectDatasetBuilder.new(dataset, map_config: MapConfig.new("cwm", root: @map_dir)).call
  end

  test "builds a dataset zip from the unified CSV and the project's map config" do
    dataset = build!
    assert dataset.succeeded?, dataset.log
    assert_equal 4, dataset.item_count

    entries = {}
    Zip::File.open(dataset.zip_path) { |zip| zip.each { |e| entries[e.name] = e.get_input_stream.read unless e.directory? } }
    assert_equal %w[ about.md assets/markers/a.png config.json items/0.json items/1.json items/2.json items/3.json locations.json searchable.json ],
      entries.keys.sort
    assert_equal "About the dummy map.\n", entries["about.md"]
    assert_equal [ "en" ], JSON.parse(entries["config.json"])["languages"], "overlay replaces the base's array"
    assert_equal JSON.parse(file_fixture("dataset-cli/expected/dummy/locations.json").read), JSON.parse(entries["locations.json"])
  end

  test "fails with the reason when the config is invalid" do
    File.write(@map_dir + "cwm/config.json", { "itemProps" => "nonsense" }.to_json)
    dataset = build!
    assert dataset.failed?
    assert_match(/itemProps/, dataset.log)
  end
end
