require "test_helper"

class DataBuilderGeocoderTest < ActiveSupport::TestCase
  test "render_template substitutes fields and collapses separators" do
    headers = %w[Address Postcode]
    row = [ "1 High St", "AB1 2CD" ]
    assert_equal "1 High St, AB1 2CD, UK",
      DataBuilder::Geocoder.render_template("{{Address}}, {{Postcode}}, UK", headers, row)
    assert_equal "AB1 2CD, UK",
      DataBuilder::Geocoder.render_template("{{Address}}, {{Postcode}}, UK", headers, [ "", "AB1 2CD" ])
    assert_equal "UK",
      DataBuilder::Geocoder.render_template("{{Missing}}, UK", headers, row)
  end

  def geocode(csv_content, spec, geocoder)
    Dir.mktmpdir do |tmp|
      inp = File.join(tmp, "in.csv")
      out = File.join(tmp, "out.csv")
      File.write(inp, csv_content)
      stats = DataBuilder::Geocoder.geocode_csv(inp, out, spec, geocoder: geocoder)
      return [ stats, CSV.read(out) ]
    end
  end

  test "geocodes rows, caches results in the DB, appends synthetic columns" do
    calls = []
    fake = ->(input) { calls << input; { lat: 51.5, lng: -3.2 } }
    csv = "Name,Address\nAlice,1 High St\nBob,1 High St\nEmpty,\n"
    spec = { "template" => "{{Address}}, UK", "prefer" => "geocode" }

    stats, rows = geocode(csv, spec, fake)

    assert_equal [ "1 High St, UK" ], calls, "second row must come from the cache"
    assert_equal 3, stats.rows
    assert_equal 1, stats.fetched
    assert_equal 1, stats.from_cache
    assert_equal %w[Name Address __geocoded_lat __geocoded_lng], rows[0]
    assert_equal [ "Alice", "1 High St", "51.5", "-3.2" ], rows[1]
    assert_equal [ "Empty", "", "", "" ], rows[3], "all-empty template fields are not geocoded"
    assert DataBuilder::GeocodeEntry.exists?(input: "1 High St, UK")
  end

  test "caches failures and counts them" do
    fake = ->(_input) { { lat: nil, lng: nil } }
    stats, rows = geocode("Name,Address\nA,Nowhere\n",
      { "template" => "{{Address}}", "prefer" => "geocode" }, fake)
    assert_equal 1, stats.failed
    assert_equal [ "A", "Nowhere", "", "" ], rows[1]
    entry = DataBuilder::GeocodeEntry.find_by(input: "Nowhere")
    assert entry
    assert_nil entry.lat

    # A rebuild hits the cached failure, not the geocoder
    boom = ->(_input) { raise "should not be called" }
    stats2, = geocode("Name,Address\nA,Nowhere\n",
      { "template" => "{{Address}}", "prefer" => "geocode" }, boom)
    assert_equal 1, stats2.from_cache
  end

  test "prefer latlng keeps column values and only geocodes the rest" do
    calls = []
    fake = ->(input) { calls << input; { lat: 1.0, lng: 2.0 } }
    csv = "Name,Address,Lat,Lng\nA,Somewhere,51.1,-3.1\nB,Elsewhere,,\n"
    spec = { "template" => "{{Address}}", "prefer" => "latlng", "latHeader" => "Lat", "lngHeader" => "Lng" }

    stats, rows = geocode(csv, spec, fake)

    assert_equal [ "Elsewhere" ], calls
    assert_equal 1, stats.from_columns
    assert_equal 1, stats.fetched
    assert_equal [ "A", "Somewhere", "51.1", "-3.1", "51.1", "-3.1" ], rows[1]
    assert_equal [ "B", "Elsewhere", "", "", "1.0", "2.0" ], rows[2]
  end

  test "prefer geocode falls back to columns when geocoding fails" do
    fake = ->(_input) { { lat: nil, lng: nil } }
    csv = "Name,Address,Lat,Lng\nA,Somewhere,51.1,-3.1\n"
    spec = { "template" => "{{Address}}", "prefer" => "geocode", "latHeader" => "Lat", "lngHeader" => "Lng" }
    stats, rows = geocode(csv, spec, fake)
    assert_equal 1, stats.from_columns
    assert_equal [ "A", "Somewhere", "51.1", "-3.1", "51.1", "-3.1" ], rows[1]
  end
end
