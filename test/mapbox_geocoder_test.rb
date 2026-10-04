require "minitest/autorun"
require "json"
require "tmpdir"
require_relative "../lib/mapbox_geocoder"

class MapboxGeocoderTest < Minitest::Test
  # Records requested URIs and answers with a canned [status, body]
  class FakeHttp
    attr_reader :uris

    def initialize(status: 200, body: { features: [] })
      @status = status
      @body = body
      @uris = []
    end

    def call(uri)
      @uris << uri
      [@status, JSON.generate(@body)]
    end
  end

  def feature(lng, lat, address, type = "address")
    { geometry: { coordinates: [lng, lat] },
      properties: { full_address: address, feature_type: type } }
  end

  def setup
    @dir = Dir.mktmpdir
    @cache = GeocodeCache.new(File.join(@dir, "geocodes.csv"))
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_query_joins_non_empty_trimmed_parts
    assert_equal "1 High St, Brecon, GB",
                 MapboxGeocoder.query([" 1 High St ", nil, "", "Brecon", "GB"])
  end

  def test_serves_cache_hits_without_a_token
    @cache["Brecon"] = GeocodeCache::Entry.new("51.9", "-3.4", "Brecon, Wales")
    http = FakeHttp.new
    geocoder = MapboxGeocoder.new(cache: @cache, token: nil, http: http)

    result = geocoder.geocode("Brecon")

    assert_equal "51.9", result.lat
    assert_equal "-3.4", result.lng
    assert_equal "Brecon, Wales", result.geocoded_address
    assert result.cache_hit
    assert_empty http.uris
  end

  def test_aborts_on_a_miss_when_no_token_is_set
    http = FakeHttp.new
    geocoder = MapboxGeocoder.new(cache: @cache, token: nil, http: http)

    result = geocoder.geocode("Brecon")

    assert_kind_of MapboxGeocoder::Failure, result
    assert result.abort
    assert_equal :no_token, geocoder.abort_reason
    assert_empty http.uris
  end

  def test_geocodes_a_miss_and_caches_it
    http = FakeHttp.new(body: { features: [feature(-3.407428, 51.944891, "Brecon, Wales")] })
    geocoder = MapboxGeocoder.new(cache: @cache, token: "tok", http: http)

    result = geocoder.geocode("Newgate Street, Brecon")

    assert_equal "51.944891", result.lat
    assert_equal "-3.407428", result.lng
    assert_equal "Brecon, Wales", result.geocoded_address
    refute result.cache_hit
    assert_equal 1, geocoder.newly_geocoded
    assert_equal "51.944891", @cache["Newgate Street, Brecon"].lat
    assert_equal "https://api.mapbox.com/search/geocode/v6/forward" \
                 "?q=Newgate%20Street%2C%20Brecon&access_token=tok",
                 http.uris.first.to_s
  end

  def test_whole_number_coordinates_have_no_decimal_point
    http = FakeHttp.new(body: { features: [feature(-3.0, 52.0, "Somewhere")] })
    geocoder = MapboxGeocoder.new(cache: @cache, token: "tok", http: http)

    result = geocoder.geocode("Somewhere")

    assert_equal "52", result.lat
    assert_equal "-3", result.lng
  end

  def test_passes_the_bbox
    http = FakeHttp.new
    geocoder = MapboxGeocoder.new(cache: @cache, token: "tok", http: http,
                                  bbox: [-5.4, 51.35, -2.6, 53.53])

    geocoder.geocode("Brecon")

    assert_match(/&bbox=-5.4,51.35,-2.6,53.53\z/, http.uris.first.to_s)
  end

  def test_prefers_the_requested_feature_type
    http = FakeHttp.new(body: { features: [feature(1, 2, "Street"),
                                           feature(3, 4, "LD3 8ED", "postcode")] })
    geocoder = MapboxGeocoder.new(cache: @cache, token: "tok", http: http,
                                  prefer_feature_type: "postcode")

    assert_equal "LD3 8ED", geocoder.geocode("Brecon").geocoded_address
  end

  def test_falls_back_to_the_first_feature
    http = FakeHttp.new(body: { features: [feature(1, 2, "Street")] })
    geocoder = MapboxGeocoder.new(cache: @cache, token: "tok", http: http,
                                  prefer_feature_type: "postcode")

    assert_equal "Street", geocoder.geocode("Brecon").geocoded_address
  end

  def test_no_result_is_a_failure_that_does_not_abort
    geocoder = MapboxGeocoder.new(cache: @cache, token: "tok", http: FakeHttp.new)

    result = geocoder.geocode("Nowhere")

    assert_kind_of MapboxGeocoder::Failure, result
    refute result.abort
    assert_equal 0, @cache.size
  end

  def test_aborts_remaining_calls_after_an_auth_failure
    http = FakeHttp.new(status: 401)
    geocoder = MapboxGeocoder.new(cache: @cache, token: "bad", http: http)

    first = geocoder.geocode("Brecon")
    second = geocoder.geocode("Hay-on-Wye")

    assert first.abort
    assert second.abort
    assert_equal :auth_failed, geocoder.abort_reason
    assert_equal 1, http.uris.size
  end

  def test_other_http_errors_do_not_abort
    geocoder = MapboxGeocoder.new(cache: @cache, token: "tok", http: FakeHttp.new(status: 500))

    result = geocoder.geocode("Brecon")

    refute result.abort
    assert_equal "Mapbox HTTP 500", result.reason
  end
end
