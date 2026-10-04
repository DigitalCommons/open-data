require "test_helper"

# Expected values come from DuckDB v1.2.0 (data-pipelines' @duckdb/node-api).
class UnifiedCsv::DuckValuesTest < ActiveSupport::TestCase
  V = UnifiedCsv::DuckValues

  test "sniffs column types as read_csv does" do
    assert_equal :bigint, V.sniff([ "1", "2", nil, " 5 " ])
    assert_equal :varchar, V.sniff([ "007", "5" ]), "leading zeros keep a column as text"
    assert_equal :double, V.sniff([ "33", "51.50", "8.6142254", "0.00005" ])
    assert_equal :double, V.sniff([ "12345678901234567890", "1" ]), "beyond int64"
    assert_equal :double, V.sniff([ "1e16", "1e15" ])
    assert_equal :boolean, V.sniff([ "TRUE", "False", "t", "f" ])
    assert_equal :varchar, V.sniff([ "+7", "8" ])
    assert_equal :varchar, V.sniff([ "1", "x" ])
    assert_equal :varchar, V.sniff([ nil, nil ])
  end

  test "renders values as DuckDB casts them to VARCHAR" do
    assert_equal "5", V.varchar(:bigint, " 5 ")
    assert_equal "33.0", V.varchar(:double, "33")
    assert_equal "51.5", V.varchar(:double, "51.50")
    assert_equal "5e-05", V.varchar(:double, "0.00005")
    assert_equal "0.0001", V.varchar(:double, "0.0001")
    assert_equal "1000000000000000.0", V.varchar(:double, "1e15")
    assert_equal "1e+16", V.varchar(:double, "1e16")
    assert_equal "1.2345678901234567e+19", V.varchar(:double, "12345678901234567890")
    assert_equal "0.30000000000000004", V.varchar(:double, "0.30000000000000004")
    assert_equal "-0.0", V.varchar(:double, "-0.0")
    assert_equal "true", V.varchar(:boolean, "TRUE")
    assert_equal " a ", V.varchar(:varchar, " a ")
    assert_nil V.varchar(:double, nil)
  end

  test "renders values as JavaScript's toString sees them from node-api" do
    assert_equal "5", V.js_string(:bigint, " 5 ")
    assert_equal "33", V.js_string(:double, "33")
    assert_equal "51.5", V.js_string(:double, "51.50")
    assert_equal "0.00005", V.js_string(:double, "0.00005")
    assert_equal "1e-7", V.js_string(:double, "0.0000001")
    assert_equal "1e+21", V.js_string(:double, "1e21")
    assert_equal "false", V.js_string(:boolean, "F")
    assert_equal "007", V.js_string(:varchar, "007")
  end
end
