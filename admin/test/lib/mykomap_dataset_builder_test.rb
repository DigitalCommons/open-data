require "test_helper"

# Golden test: build the monolith's dataset-cli fixture and compare the
# output structurally with the expected files the TS implementation wrote.
class MykomapDatasetBuilderTest < ActiveSupport::TestCase
  test "builds the dummy fixture identically to the TS implementation" do
    config = Mykomap::Config.parse(JSON.parse(File.read(file_fixture("dataset-cli/config.json"))))
    expected_dir = file_fixture("dataset-cli/expected/dummy")

    Dir.mktmpdir do |tmp|
      out = File.join(tmp, "dummy")
      stats = Mykomap::DatasetBuilder.build_dataset_from_csv(
        config, file_fixture("dataset-cli/dummy.csv").to_s, out
      )
      assert_equal 4, stats.written
      assert_empty stats.errors

      expected_locations = JSON.parse(File.read(expected_dir + "locations.json"))
      assert_equal expected_locations, JSON.parse(File.read(File.join(out, "locations.json")))

      expected_searchable = JSON.parse(File.read(expected_dir + "searchable.json"))
      assert_equal expected_searchable, JSON.parse(File.read(File.join(out, "searchable.json")))

      4.times do |ix|
        expected_item = JSON.parse(File.read(expected_dir + "items/#{ix}.json"))
        assert_equal expected_item, JSON.parse(File.read(File.join(out, "items", "#{ix}.json"))),
          "item #{ix} differs"
      end

      assert_match(/\Acreated on: /, File.read(File.join(out, "about.md")))
    end
  end

  test "skips duplicate ids and records errors" do
    config = Mykomap::Config.parse(JSON.parse(File.read(file_fixture("dataset-cli/config.json"))))
    Dir.mktmpdir do |tmp|
      csv = File.join(tmp, "dupes.csv")
      File.write(csv, <<~CSV)
        Identifier,Name,Desc,Address,Websites,Activity,Other Activities,Latitude,Longitude,Geocoded Latitude,Geocoded Longitude,Validated
        aaa,First,,,,,,,,,,
        aaa,Second,,,,,,,,,,
      CSV
      stats = Mykomap::DatasetBuilder.build_dataset_from_csv(config, csv, File.join(tmp, "out"))
      assert_equal 1, stats.written
      assert_equal 1, stats.errors.length
      assert_equal "duplicate ID", stats.errors.first["message"]
    end
  end

  test "invalid vocab values fail the build" do
    config = Mykomap::Config.parse(JSON.parse(File.read(file_fixture("dataset-cli/config.json"))))
    Dir.mktmpdir do |tmp|
      csv = File.join(tmp, "bad.csv")
      File.write(csv, <<~CSV)
        Identifier,Name,Desc,Address,Websites,Activity,Other Activities,Latitude,Longitude,Geocoded Latitude,Geocoded Longitude,Validated
        aaa,First,,,,NOT_A_TERM,,,,,,
      CSV
      error = assert_raises(Mykomap::CsvParser::ValidationError) do
        Mykomap::DatasetBuilder.build_dataset_from_csv(config, csv, File.join(tmp, "out"))
      end
      assert_match(/vocab URI/, error.message)
    end
  end

  test "missing CSV headers fail the build" do
    config = Mykomap::Config.parse(JSON.parse(File.read(file_fixture("dataset-cli/config.json"))))
    Dir.mktmpdir do |tmp|
      csv = File.join(tmp, "short.csv")
      File.write(csv, "Identifier,Name\naaa,First\n")
      error = assert_raises(Mykomap::CsvParser::ValidationError) do
        Mykomap::DatasetBuilder.build_dataset_from_csv(config, csv, File.join(tmp, "out"))
      end
      assert_match(/missing headers/, error.message)
    end
  end

  test "custom markers add an icon index to locations" do
    raw = JSON.parse(File.read(file_fixture("dataset-cli/config.json")))
    raw["ui"]["customMarkers"] = {
      "marker_property_name" => "activity",
      "markerIcons" => [ "a.png", "b.png" ],
      "termsToIconIndex" => { "default" => 0, "AM60" => 1 }
    }
    config = Mykomap::Config.parse(raw)
    Dir.mktmpdir do |tmp|
      Mykomap::DatasetBuilder.build_dataset_from_csv(
        config, file_fixture("dataset-cli/dummy.csv").to_s, File.join(tmp, "out")
      )
      locations = JSON.parse(File.read(File.join(tmp, "out/locations.json")))
      # bbb has activity AM60 -> icon 1; aaa has AM130 -> default 0
      assert_equal 3, locations[1].length
      assert_equal 1, locations[1][2]
      assert_equal 0, locations[0][2]
    end
  end
end
