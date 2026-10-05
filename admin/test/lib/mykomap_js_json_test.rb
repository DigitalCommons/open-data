require "test_helper"

# Number output must match the monolith's (JavaScript) byte for byte.
class MykomapJsJsonTest < ActiveSupport::TestCase
  test "writes floats as JavaScript does" do
    assert_equal "[15.14093,33,-0.00001,1e+21,51.5]", Mykomap::JsJson.generate([ 15.14093, 33.0, -0.00001, 1e21, 51.5 ])
    assert_equal "{\n  \"lat\": 15.14093,\n  \"n\": 2\n}", Mykomap::JsJson.pretty_generate({ "lat" => 15.14093, "n" => 2 })
  end

  test "rounds coordinates as Number(value.toFixed(5)) does" do
    writer = Mykomap::DatasetWriter.allocate
    assert_equal [ 88.05309, 17.02503, -0.00001, 33.0, 51.12346, 15.14093 ],
      [ 88.053095, 17.025035, -0.000005, 33.0, 51.123456, 15.1409278 ].map { |v| writer.round5(v) }
  end
end
