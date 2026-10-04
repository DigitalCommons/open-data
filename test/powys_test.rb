require "minitest/autorun"
require_relative "../lib/powys"

class PowysTest < Minitest::Test
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

  QUERY = "Newgate Street, Brecon, LD3 8ED, GB".freeze

  def row(overrides = {})
    {
      "ID" => "1",
      "Title_Eng" => "Brecon: Newgate\r\n Allotments",
      "Title_Cym" => "Aberhonddu: Rhandir",
      "Town" => "Brecon",
      "Category" => "Community growing",
      "Subcategory" => "Allotments",
      "Text for popup" => "Line one\r\nLine two",
      "Text for popup_Cym" => "Llinell",
      "Address" => "Newgate Street\r\nBrecon",
      "Postcode" => "LD3 8ED",
      "Contact name" => "Someone",
      "Email address" => "a@example.org",
      "Phone number" => "01874",
      "Link" => "https://example.org",
      "Geocode" => "",
    }.merge(overrides)
  end

  def located
    FakeGeocoder.new(QUERY => MapboxGeocoder::Result.new("51.944891", "-3.407428", "LD3 8ED, Brecon", true))
  end

  def convert(rows, language = "eng", geocoder = located)
    Powys.convert(rows, geocoder, Powys.vocabs, language)
  end

  def test_read_drops_the_preamble_line_and_rows_without_an_id
    text = "12,,,These columns are inferred\r\n" \
           "ID,Title_Eng,Address\r\n" \
           "1,One,\"Street\nTown\"\r\n" \
           ",Blank,x\r\n" \
           "2,Two,y\r\n"

    rows = Powys.read(text)

    assert_equal %w[1 2], rows.map { |r| r["ID"] }
    assert_equal "Street\nTown", rows.first["Address"]
  end

  def test_read_gives_empty_strings_for_empty_fields
    rows = Powys.read("notes\r\nID,Address,Postcode\r\n1,,\r\n")

    assert_equal({ "ID" => "1", "Address" => "", "Postcode" => "" }, rows.first)
  end

  def test_query_joins_address_lines_and_adds_postcode_and_country
    assert_equal "Newgate Street, Brecon, LD3 8ED, GB",
                 Powys.query("Address" => "Newgate Street\nBrecon", "Postcode" => "LD3 8ED")
  end

  def test_maps_an_english_row
    out, fails = convert([row("Address" => "Newgate Street\nBrecon")])

    assert_empty fails
    assert_equal({
      "Identifier" => "1",
      "Name" => "Brecon: Newgate Allotments",
      "Description" => "Line one\nLine two",
      "Street Address" => "Newgate Street\nBrecon",
      "Website" => "https://example.org",
      "Primary Food System Category ID" => "cg",
      "Food System Category IDs" => "cg;cg-al",
      "Locality ID" => "br",
      "Geo Container Latitude" => "51.944891",
      "Geo Container Longitude" => "-3.407428",
      "Geo Container Confidence" => "51",
      "Geocoded Address" => "LD3 8ED, Brecon",
      "Contact name" => "Someone",
      "Email address" => "a@example.org",
      "Phone number" => "01874",
    }, out.first)
  end

  def test_welsh_uses_the_welsh_title_and_popup_without_fallback
    out, = convert([row("Address" => "Newgate Street\nBrecon", "Text for popup_Cym" => "")], "cym")

    assert_equal "Aberhonddu: Rhandir", out.first["Name"]
    assert_equal "", out.first["Description"]
  end

  def test_unmatched_categories_are_left_empty
    out, = convert([row("Address" => "Newgate Street\nBrecon", "Category" => "Unknown",
                        "Subcategory" => "Agricultural show", "Town" => "Nowhere")])

    assert_nil out.first["Primary Food System Category ID"]
    assert_equal ";", out.first["Food System Category IDs"]
    assert_nil out.first["Locality ID"]
  end

  def test_sheet_geocode_column_skips_geocoding
    geocoder = FakeGeocoder.new
    out, = convert([row("Geocode" => "51.902887738948564, -3.1934022695659063")], "eng", geocoder)

    assert_empty geocoder.queries
    assert_equal "51.902887738948564", out.first["Geo Container Latitude"]
    assert_equal "-3.1934022695659063", out.first["Geo Container Longitude"]
    assert_equal "undefined", out.first["Geocoded Address"]
  end

  def test_coordinates_are_normalised_like_javascript_numbers
    geocoder = FakeGeocoder.new
    out, = convert([row("Geocode" => "52.10, -3.0")], "eng", geocoder)

    assert_equal "52.1", out.first["Geo Container Latitude"]
    assert_equal "-3", out.first["Geo Container Longitude"]
  end

  def test_rows_that_fail_to_geocode_are_kept_without_coordinates
    out, fails = convert([row], "eng", FakeGeocoder.new)

    assert_equal 1, out.size
    assert_nil out.first["Geo Container Latitude"]
    assert_equal "51", out.first["Geo Container Confidence"]
    assert_equal [["Brecon: Newgate\r\n Allotments", "no result from Mapbox"]], fails
  end

  def test_sorts_by_name
    geocoder = FakeGeocoder.new
    rows = [row("ID" => "1", "Title_Eng" => "b", "Geocode" => "1, 2"),
            row("ID" => "2", "Title_Eng" => "a", "Geocode" => "1, 2")]

    out, = convert(rows, "eng", geocoder)

    assert_equal %w[2 1], out.map { |r| r["Identifier"] }
  end
end
