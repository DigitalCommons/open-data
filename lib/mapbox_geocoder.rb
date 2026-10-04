require "json"
require "net/http"
require "uri"
require_relative "geocode_cache"

# Geocodes with the Mapbox Search v6 forward API through a GeocodeCache.
#
# Cache hits need no token, so a run where every query is cached works
# without one. A missing token on a cache miss, or a 401/403 from Mapbox,
# stops all further Mapbox calls for this geocoder; the caller decides
# whether that fails the run.
class MapboxGeocoder
  ENDPOINT = "https://api.mapbox.com/search/geocode/v6/forward".freeze

  Result = Struct.new(:lat, :lng, :geocoded_address, :cache_hit)
  Failure = Struct.new(:reason, :abort)

  # Fetches a URI and returns [status, body]
  HTTP_GET = lambda do |uri|
    response = Net::HTTP.get_response(uri)
    [response.code.to_i, response.body]
  end

  attr_reader :abort_reason, :newly_geocoded

  # Joins the non-empty trimmed address parts with ", "
  def self.query(parts)
    parts.map { |part| part.to_s.strip }.reject(&:empty?).join(", ")
  end

  # Formats a number like JavaScript's String(number), which wrote the
  # existing caches and outputs
  def self.format_coordinate(value)
    value == value.to_i ? value.to_i.to_s : value.to_s
  end

  # bbox - [west, south, east, north] to restrict results to
  # prefer_feature_type - a Mapbox feature_type (e.g. "postcode") to pick
  # over the first result when present
  def initialize(cache:, token:, bbox: nil, prefer_feature_type: nil, http: HTTP_GET)
    @cache = cache
    @token = token
    @bbox = bbox
    @prefer_feature_type = prefer_feature_type
    @http = http
    @abort_reason = nil
    @newly_geocoded = 0
  end

  # Returns a Result or a Failure
  def geocode(query)
    cached = @cache[query]
    return Result.new(cached.lat, cached.lng, cached.geocoded_address, true) if cached
    return Failure.new("skipped (#{@abort_reason})", true) if @abort_reason

    if @token.to_s.empty?
      @abort_reason = :no_token
      return Failure.new("Mapbox token not set", true)
    end

    status, body = @http.call(request_uri(query))
    if status == 401 || status == 403
      @abort_reason = :auth_failed
      return Failure.new("Mapbox auth failed (HTTP #{status})", true)
    end
    return Failure.new("Mapbox HTTP #{status}", false) unless status == 200

    feature = pick_feature(JSON.parse(body)["features"] || [])
    return Failure.new("no result from Mapbox", false) unless feature

    lng, lat = feature["geometry"]["coordinates"].map { |value| self.class.format_coordinate(value) }
    entry = GeocodeCache::Entry.new(lat, lng, feature["properties"]["full_address"])
    @cache[query] = entry
    @newly_geocoded += 1
    Result.new(entry.lat, entry.lng, entry.geocoded_address, false)
  rescue SystemCallError, IOError, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    Failure.new("network error: #{e.message}", false)
  end

  def save
    @cache.save
  end

  private

  def request_uri(query)
    params = "q=#{URI.encode_uri_component(query)}&access_token=#{@token}"
    params += "&bbox=#{@bbox.join(',')}" if @bbox
    URI("#{ENDPOINT}?#{params}")
  end

  def pick_feature(features)
    preferred = features.find { |f| f.dig("properties", "feature_type") == @prefer_feature_type } if @prefer_feature_type
    preferred || features.first
  end

end
