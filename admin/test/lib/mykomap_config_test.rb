require "test_helper"

class MykomapConfigTest < ActiveSupport::TestCase
  def fixture_config
    JSON.parse(File.read(file_fixture("dataset-cli/config.json")))
  end

  test "parses the fixture config and materialises popup defaults" do
    config = Mykomap::Config.parse(fixture_config)
    assert_equal "70%", config["popup"]["leftPaneWidth"]
    assert_equal %w[en], config["languages"]
    assert_equal "value", config["itemProps"]["id"]["type"]
    assert_equal "am:", config["itemProps"]["activity"]["uri"]
  end

  test "materialises popup item defaults" do
    raw = fixture_config
    raw["popup"]["leftPane"] = [ { "itemProp" => "name" } ]
    config = Mykomap::Config.parse(raw)
    item = config["popup"]["leftPane"].first
    assert_equal "text", item["valueStyle"]
    assert_equal false, item["showBullets"]
    assert_equal false, item["showLabel"]
    assert_equal "", item["hyperlinkBaseUri"]
    assert_equal false, item["analyticOnClick"]
  end

  test "strips unknown keys" do
    raw = fixture_config
    raw["bogus"] = 1
    raw["ui"]["bogus"] = 2
    config = Mykomap::Config.parse(raw)
    assert_not config.key?("bogus")
    assert_not config["ui"].key?("bogus")
  end

  test "rejects a config without an id prop" do
    raw = fixture_config
    raw["itemProps"].delete("id")
    error = assert_raises(Mykomap::Config::Invalid) { Mykomap::Config.parse(raw) }
    assert_match(/itemProps.id/, error.message)
  end

  test "rejects invalid languages, vocab URIs and cron-like garbage" do
    raw = fixture_config
    raw["languages"] = [ "xx" ]
    raw["itemProps"]["activity"]["uri"] = "not a uri"
    error = assert_raises(Mykomap::Config::Invalid) { Mykomap::Config.parse(raw) }
    assert_match(/languages.0/, error.message)
    assert_match(/activity.uri/, error.message)
  end

  test "validates submaps" do
    raw = fixture_config
    raw["submaps"] = {
      "good" => { "lockedFilter" => [ "activity:AM60" ], "title" => "Food" },
      "bad" => { "lockedFilter" => [] }
    }
    error = assert_raises(Mykomap::Config::Invalid) { Mykomap::Config.parse(raw) }
    assert_match(/submaps.bad.lockedFilter/, error.message)

    raw["submaps"].delete("bad")
    config = Mykomap::Config.parse(raw)
    assert_equal [ "activity:AM60" ], config["submaps"]["good"]["lockedFilter"]
  end

  test "rejects a filterable id prop" do
    raw = fixture_config
    raw["itemProps"]["id"]["filter"] = true
    error = assert_raises(Mykomap::Config::Invalid) { Mykomap::Config.parse(raw) }
    assert_match(/id/, error.message)
  end
end
