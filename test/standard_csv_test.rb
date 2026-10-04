require "minitest/autorun"
require "tmpdir"
require_relative "../lib/standard_csv"

class StandardCsvTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "generated-data", "standard.csv")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_has_the_data_pipelines_columns_in_order
    assert_equal 34, StandardCsv::COLUMNS.size
    assert_equal %w[Identifier Name Description], StandardCsv::COLUMNS.first(3)
    assert_equal %w[Domains Dataset], StandardCsv::COLUMNS.last(2)
  end

  def test_writes_only_the_header_when_there_are_no_rows
    StandardCsv.write(@path, [])

    assert_equal StandardCsv::COLUMNS.join(",") + "\n", File.read(@path)
  end

  def test_leaves_missing_and_empty_values_unquoted
    StandardCsv.write(@path, [{ "Identifier" => "a", "Name" => "", "Dataset" => "nfca" }])

    row = File.read(@path).lines.last
    assert_equal "a" + "," * 33 + "nfca", row
  end

  def test_quotes_values_containing_commas
    StandardCsv.write(@path, [{ "Identifier" => "a", "Name" => "Smith, Jones" }])

    assert_match(/\Aa,"Smith, Jones",/, File.read(@path).lines.last)
  end

  def test_rejects_unknown_columns
    assert_raises(ArgumentError) { StandardCsv.write(@path, [{ "Nmae" => "x" }]) }
  end

  def test_country_ids
    assert_equal "US", StandardCsv::COUNTRY_IDS["USA"]
    assert_equal "GB", StandardCsv::COUNTRY_IDS["United Kingdom"]
  end
end
