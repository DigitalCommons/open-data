require "minitest/autorun"
require_relative "../comn/comn"

class ComnTest < Minitest::Test
  # Answers from a fixed table of query => result and records the queries
  class FakeGeocoder
    attr_reader :queries

    def initialize(results = {})
      @results = results
      @queries = []
    end

    def geocode(query)
      @queries << query
      @results.fetch(query) { MapboxGeocoder::Failure.new("no result from Mapbox", false) }
    end
  end

  QUERY = "100 Main St, Suite 2, Minneapolis, Minnesota, 55401, United States".freeze

  def row(overrides = {})
    {
      "ID" => "apex-1",
      "Title" => " Seward Co-op ",
      "Website URL" => " https://seward.coop ; https://example.org ",
      "Organisational Structure" => "Cooperative",
      "Membership Type" => "consumer/users",
      "Activities" => "Agriculture, Mining;Professional",
      "Text for popup" => "A grocery co-op",
      "Street Address" => " 100 Main St ",
      "Street Address 2" => "Suite 2",
      "City" => "Minneapolis",
      "State/Region" => "Minnesota",
      "Postcode/Zip" => "55401",
      "Country/Region" => "United States",
      "Contact name" => "Someone",
      "Email address" => "info@seward.coop",
      "Phone number" => "555 1234",
      "Last update?" => "2026",
      "Latitude" => "",
      "Longitude" => "",
    }.merge(overrides)
  end

  def located
    FakeGeocoder.new(QUERY => MapboxGeocoder::Result.new("44.97", "-93.26", "Minneapolis, MN", true))
  end

  def convert(rows, geocoder = located)
    Comn.convert(rows, geocoder, Comn.vocabs)
  end

  def test_maps_a_row_to_the_standard_columns
    out, fails = convert([row])

    assert_empty fails
    assert_equal({
      "Identifier" => "apex-1",
      "Name" => "Seward Co-op",
      "Description" => "A grocery co-op",
      "Organisational Structure" => "OS115",
      "Primary Activity" => "ICA10",
      "Activities" => "ICA10;ICA100;ICA110",
      "Street Address" => "100 Main St, Suite 2",
      "Locality" => "Minneapolis",
      "Region" => "Minnesota",
      "Postcode" => "55401",
      "Country ID" => "US",
      "Website" => "https://seward.coop;https://example.org",
      "Phone" => "555 1234",
      "Email" => "info@seward.coop",
      "Membership Type" => "BMT10",
      "Latitude" => "44.97",
      "Longitude" => "-93.26",
      "Geocoded Address" => "Minneapolis, MN",
      "Dataset" => "comn",
    }, out.first)
  end

  def test_country_falls_back_to_the_upper_cased_vocab_code
    query = QUERY.sub("United States", "Canada ")
    geocoder = FakeGeocoder.new(query.strip => MapboxGeocoder::Result.new("1", "2", "x", true))
    out, = convert([row("Country/Region" => "Canada ")], geocoder)
    assert_equal "CA", out.first["Country ID"]

    query = QUERY.sub("United States", "France")
    geocoder = FakeGeocoder.new(query => MapboxGeocoder::Result.new("1", "2", "x", true))
    out, = convert([row("Country/Region" => "France")], geocoder)
    assert_equal "FR", out.first["Country ID"]
  end

  def test_sheet_coordinates_skip_geocoding
    geocoder = FakeGeocoder.new
    out, = convert([row("Latitude" => "44.9", "Longitude" => "-93.2")], geocoder)

    assert_empty geocoder.queries
    assert_equal "44.9", out.first["Latitude"]
    assert_equal "-93.2", out.first["Longitude"]
    assert_equal QUERY, out.first["Geocoded Address"]
  end

  def test_invalid_sheet_coordinates_raise
    assert_raises(ArgumentError) { convert([row("Latitude" => "north", "Longitude" => "-93.2")]) }
  end

  def test_drops_rows_with_neither_id_nor_title
    out, fails = convert([row("ID" => " ", "Title" => "")], FakeGeocoder.new)

    assert_empty out
    assert_empty fails
  end

  def test_rejects_missing_or_invalid_ids
    assert_raises(ArgumentError) { convert([row("ID" => "")]) }
    assert_raises(ArgumentError) { convert([row("ID" => "apex 1")]) }
  end

  def test_rejects_duplicate_ids
    error = assert_raises(ArgumentError) { convert([row, row("Title" => "Other")]) }
    assert_match(/Duplicate ID apex-1/, error.message)
  end

  def test_unknown_vocab_labels_raise
    error = assert_raises(ArgumentError) { convert([row("Membership Type" => "Shareholders")]) }
    assert_match(/Membership Type.*Shareholders/, error.message)
  end

  def test_drops_rows_that_fail_to_geocode
    out, fails = convert([row], FakeGeocoder.new)

    assert_empty out
    assert_equal [["Seward Co-op", "no result from Mapbox"]], fails
  end

  def test_no_rows_gives_no_output
    assert_equal [[], []], convert([])
  end
end
