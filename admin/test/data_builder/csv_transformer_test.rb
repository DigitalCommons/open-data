require "test_helper"

class DataBuilderCsvTransformerTest < ActiveSupport::TestCase
  test "maps values, splits multis and passes unmapped values through" do
    Dir.mktmpdir do |tmp|
      inp = File.join(tmp, "in.csv")
      out = File.join(tmp, "out.csv")
      File.write(inp, <<~CSV)
        Name,Activity,Tags
        Alice,Community growing,Food;Farming
        Bob,Unknown thing,Food
      CSV
      value_maps = {
        "Activity" => { "Community growing" => "cg", "Unknown thing" => "ut" },
        "Tags" => { "Food" => "AM60", "Farming" => "AM130" }
      }
      DataBuilder::CsvTransformer.transform(inp, out, value_maps, Set.new([ "Tags" ]))

      rows = CSV.read(out)
      assert_equal %w[Name Activity Tags], rows[0]
      assert_equal [ "Alice", "cg", "AM60;AM130" ], rows[1]
      assert_equal [ "Bob", "ut", "AM60" ], rows[2]
    end
  end

  test "trims when matching and leaves unmapped values unchanged" do
    Dir.mktmpdir do |tmp|
      inp = File.join(tmp, "in.csv")
      out = File.join(tmp, "out.csv")
      File.write(inp, "A\n mapped \nunmapped\n\n")
      DataBuilder::CsvTransformer.transform(inp, out, { "A" => { "mapped" => "m1" } }, Set.new)
      rows = CSV.read(out)
      assert_equal [ "m1" ], rows[1], "trimmed match should map"
      assert_equal [ "unmapped" ], rows[2]
    end
  end
end
