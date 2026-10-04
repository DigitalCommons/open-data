require "minitest/autorun"
require "tmpdir"
require_relative "../nfca/nfca"

class NfcaTest < Minitest::Test
  # Answers from a fixed table of query => result
  class FakeGeocoder
    def initialize(results)
      @results = results
    end

    def geocode(query)
      @results.fetch(query) { MapboxGeocoder::Failure.new("no result from Mapbox", false) }
    end
  end

  def row(overrides = {})
    {
      "Company name" => "4th Street Food Co-op (Good Harvest)",
      "Company Domain Name (If known)" => "https://4thstreetfoodcoop.org",
      "Co-op Sector" => "Retail",
      "Industry" => "Grocery",
      "Street Address" => "58 East 4th Street",
      "Street Address 2" => "",
      "City" => "New York",
      "State/Region" => "NY",
      "Country/Region" => "USA",
    }.merge(overrides)
  end

  def located(query, lat = "40.65127", lng = "-73.97812", address = "58 East 4th Street, Brooklyn")
    { query => MapboxGeocoder::Result.new(lat, lng, address, true) }
  end

  def test_slugify
    assert_equal "4-corners-food-co-op-huddle-farms-village-market",
                 Nfca.slugify("4 Corners Food Co-op (Huddle Farms Village Market)")
    assert_equal "a-b", Nfca.slugify("--A & B!")
  end

  def test_query_joins_both_street_lines
    assert_equal "1 Main St, Unit 2, Waterville, NY, USA",
                 Nfca.query(row("Street Address" => "1 Main St", "Street Address 2" => "Unit 2",
                                "City" => "Waterville"))
  end

  def test_maps_a_row_to_the_standard_columns
    out, fails = Nfca.convert([row], FakeGeocoder.new(located("58 East 4th Street, New York, NY, USA")))

    assert_empty fails
    assert_equal({
      "Identifier" => "4th-street-food-co-op-good-harvest",
      "Name" => "4th Street Food Co-op (Good Harvest)",
      "Primary Activity" => "ICA240",
      "Street Address" => "58 East 4th Street",
      "Locality" => "New York",
      "Region" => "NY",
      "Country ID" => "US",
      "Website" => "https://4thstreetfoodcoop.org",
      "Latitude" => "40.65127",
      "Longitude" => "-73.97812",
      "Geocoded Address" => "58 East 4th Street, Brooklyn",
      "Sector" => "Retail",
      "Dataset" => "nfca",
    }, out.first)
  end

  def test_unknown_countries_pass_through
    query = "58 East 4th Street, New York, NY, Mexico"
    out, = Nfca.convert([row("Country/Region" => " Mexico ")],
                        FakeGeocoder.new(located(query)))

    assert_equal "Mexico", out.first["Country ID"]
  end

  def test_skips_example_rows
    out, fails = Nfca.convert([row("Company name" => "Example - Suppliers")], FakeGeocoder.new({}))

    assert_empty out
    assert_empty fails
  end

  def test_drops_rows_that_fail_to_geocode
    out, fails = Nfca.convert([row], FakeGeocoder.new({}))

    assert_empty out
    assert_equal [["4th Street Food Co-op (Good Harvest)", "no result from Mapbox"]], fails
  end

  def test_stops_after_an_aborting_failure
    aborting = Class.new do
      attr_reader :calls

      def geocode(_query)
        @calls = (@calls || 0) + 1
        MapboxGeocoder::Failure.new("Mapbox token not set", true)
      end
    end.new

    _, fails = Nfca.convert([row, row("Company name" => "Other")], aborting)

    assert_equal 1, aborting.calls
    assert_equal 1, fails.size
  end

  def test_unmapped_sector_raises
    error = assert_raises(ArgumentError) do
      Nfca.convert([row("Co-op Sector" => "Housing")],
                   FakeGeocoder.new(located("58 East 4th Street, New York, NY, USA")))
    end
    assert_match(/Housing/, error.message)
  end
end
