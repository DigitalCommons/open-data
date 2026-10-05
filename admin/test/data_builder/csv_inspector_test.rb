require "test_helper"

class DataBuilderCsvInspectorTest < ActiveSupport::TestCase
  def write_csv(dir, content)
    path = File.join(dir, "test.csv")
    File.binwrite(path, content)
    path
  end

  test "inspects headers, counts, distinct values, numeric and semicolon stats" do
    Dir.mktmpdir do |tmp|
      path = write_csv(tmp, <<~CSV)
        Name,Age,Tags,Empty
        Alice,34,a;b,
        Bob,55,b,
        Carol,,a;c,
      CSV
      result = DataBuilder::CsvInspector.inspect_csv(path)
      assert_equal %w[Name Age Tags Empty], result["headers"]
      assert_equal 3, result["rowCount"]
      assert_equal 3, result["sampleRows"].length

      name, age, tags, empty = result["columns"]
      assert_equal 3, name["nonEmpty"]
      assert_equal false, name["allNumeric"]
      assert_equal true, age["allNumeric"]
      assert_equal 2, age["nonEmpty"]
      assert_equal 2, tags["semicolons"]
      assert_equal [ "a;b", "b", "a;c" ], tags["distinct"]
      assert_equal false, empty["allNumeric"], "empty columns can't be called numeric"
    end
  end

  test "caps distinct values and flags truncation" do
    Dir.mktmpdir do |tmp|
      rows = (1..10).map { |i| "v#{i}" }.join("\n")
      path = write_csv(tmp, "Col\n#{rows}\n")
      result = DataBuilder::CsvInspector.inspect_csv(path, max_distinct: 5)
      col = result["columns"].first
      assert_equal 5, col["distinct"].length
      assert col["distinctTruncated"]
    end
  end

  test "strips a UTF-8 BOM" do
    Dir.mktmpdir do |tmp|
      path = write_csv(tmp, "\xEF\xBB\xBFName,Age\nAlice,1\n")
      skipped = DataBuilder::CsvInspector.strip_leading_junk(path)
      assert_equal 0, skipped
      assert_equal "Name,Age", File.read(path).lines.first.chomp
    end
  end

  test "strips junk lines above the title row" do
    Dir.mktmpdir do |tmp|
      path = write_csv(tmp, "Some note,,,\n,,,\nName,Age,City,Country\nAlice,1,X,Y\n")
      skipped = DataBuilder::CsvInspector.strip_leading_junk(path)
      assert_equal 2, skipped
      assert_equal "Name,Age,City,Country", File.read(path).lines.first.chomp
    end
  end

  test "leaves a clean CSV alone" do
    Dir.mktmpdir do |tmp|
      path = write_csv(tmp, "Name,Age\nAlice,1\n")
      assert_equal 0, DataBuilder::CsvInspector.strip_leading_junk(path)
      assert_equal "Name,Age\nAlice,1\n", File.read(path)
    end
  end

  test "gives up after five junk lines" do
    Dir.mktmpdir do |tmp|
      junk = ",,,\n" * 7
      path = write_csv(tmp, junk + "Name,Age\nAlice,1\n")
      assert_equal 5, DataBuilder::CsvInspector.strip_leading_junk(path)
      assert_not_equal "Name,Age", File.read(path).lines.first.chomp
    end
  end
end
