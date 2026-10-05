require "test_helper"

class MapConfigTest < ActiveSupport::TestCase
  test "merge follows data-pipelines: objects merge, arrays and scalars replace, null removes" do
    base = { "a" => 1, "ui" => { "x" => 1, "y" => [ 1, 2 ], "z" => "keep" }, "gone" => true }
    overlay = { "ui" => { "y" => [ 3 ], "new" => { "n" => 1 } }, "gone" => nil, "b" => 2 }
    merged = MapConfig.merge(base, overlay)

    assert_equal({ "a" => 1, "ui" => { "x" => 1, "y" => [ 3 ], "z" => "keep", "new" => { "n" => 1 } }, "b" => 2 }, merged)
    assert_equal %w[ a ui b ], merged.keys, "base keys first, in base order"
  end

  test "projects with a map config in admin/mykomaps" do
    assert MapConfig.for("cwm")
    assert MapConfig.for("workers-coop")
    assert_nil MapConfig.for("powys")
  end

  test "the CWM config merges and validates" do
    config = MapConfig.for("cwm").config
    assert_equal "Identifier", config.dig("itemProps", "id", "from")
    assert config.dig("submaps", "co-minnesota")
    Mykomap::Config.parse(config)
  end

  test "lists the about text and asset files to copy" do
    map = MapConfig.for("cwm")
    assert map.about_path.file?
    assert_includes map.asset_files.map { |path| path.relative_path_from(map.assets_dir).to_s }, "markers/dotcoop.png"
  end

  test "json_text writes numbers as JavaScript does" do
    assert_equal "{\n  \"a\": -89,\n  \"b\": 51.5,\n  \"c\": [\n    2\n  ]\n}\n", MapConfig.json_text({ "a" => -89.0, "b" => 51.5, "c" => [ 2.0 ] })
  end
end
