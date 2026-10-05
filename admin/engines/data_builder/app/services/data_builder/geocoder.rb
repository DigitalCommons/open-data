require "csv"
require "net/http"
require "json"

module DataBuilder
  # Geocoding of CSV rows via a {{Column}} template, ported from
  # apps/back-end/src/dataset/geocode.ts. Results (including failures) are
  # cached in the mykomap_geocode_entries table.
  module Geocoder
    GEOCODED_LAT = "__geocoded_lat".freeze
    GEOCODED_LNG = "__geocoded_lng".freeze

    Stats = Struct.new(:rows, :from_columns, :from_cache, :fetched, :failed, keyword_init: true) do
      def message
        "Geocoding: #{rows} rows, #{from_columns} from lat/lng columns, " \
          "#{from_cache} from the cache, #{fetched} newly geocoded, #{failed} not found."
      end
    end

    module_function

    # Renders a {{Field}} template against a CSV row; collapses separator
    # runs left by empty fields.
    def render_template(template, headers, row)
      template
        .gsub(/\{\{(.*?)\}\}/) do
          ix = headers.index(Regexp.last_match(1).to_s.strip)
          ix.nil? ? "" : (row[ix] || "").strip
        end
        .gsub(/(\s*,\s*)+/, ", ")
        .gsub(/\A[\s,]+|[\s,]+\z/, "")
    end

    def template_fields(template)
      template.scan(/\{\{(.*?)\}\}/).map { |m| m[0].strip }
    end

    # The default geocoder: a Nominatim-compatible search endpoint, throttled.
    def nominatim
      url = ENV["GEOCODER_URL"] || "https://nominatim.openstreetmap.org/search"
      interval = (ENV["GEOCODER_INTERVAL_MS"] || 1100).to_f / 1000
      last = 0.0

      lambda do |input|
        wait = last + interval - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sleep(wait) if wait > 0
        last = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          uri = URI("#{url}?format=json&limit=1&q=#{CGI.escape(input)}")
          res = Net::HTTP.get_response(uri, { "User-Agent" => "MykoMap-admin/1.0 (dataset builder)" })
          raise "geocoder responded #{res.code}" unless res.is_a?(Net::HTTPSuccess)
          hit = JSON.parse(res.body).first
          lat = Float(hit&.dig("lat"), exception: false)
          lng = Float(hit&.dig("lon"), exception: false)
          return { lat: lat, lng: lng } if lat && lng
          { lat: nil, lng: nil }
        rescue => e
          # nil = transient error, distinct from a cacheable "not found"
          Rails.logger.error("geocoding '#{input}' failed: #{e}")
          nil
        end
      end
    end

    def number_or_nil(value)
      return nil if value.nil? || value.strip == ""
      n = Float(value, exception: false)
      n&.finite? ? n : nil
    end

    # Geocodes a CSV, writing a copy with __geocoded_lat/__geocoded_lng
    # appended. spec keys: "template", "prefer" ("latlng"|"geocode"),
    # "latHeader", "lngHeader".
    def geocode_csv(in_path, out_path, spec, geocoder: nominatim)
      headers = nil
      stats = Stats.new(rows: 0, from_columns: 0, from_cache: 0, fetched: 0, failed: 0)
      field_ixs = nil
      lat_ix = lng_ix = nil

      File.open(out_path, "w") do |out|
        CSV.foreach(in_path, encoding: "bom|utf-8", liberal_parsing: true) do |row|
          row = row.map { |v| v.nil? ? "" : v.to_s }
          if headers.nil?
            headers = row
            lat_ix = spec["latHeader"] ? headers.index(spec["latHeader"]) : nil
            lng_ix = spec["lngHeader"] ? headers.index(spec["lngHeader"]) : nil
            out.write(CSV.generate_line(headers + [ GEOCODED_LAT, GEOCODED_LNG ], row_sep: "\r\n"))
            next
          end
          stats.rows += 1

          col_lat = lat_ix && number_or_nil(row[lat_ix])
          col_lng = lng_ix && number_or_nil(row[lng_ix])
          have_columns = !col_lat.nil? && !col_lng.nil?

          result = { lat: nil, lng: nil }
          if spec["prefer"] == "latlng" && have_columns
            result = { lat: col_lat, lng: col_lng }
            stats.from_columns += 1
          else
            field_ixs ||= template_fields(spec["template"]).map { |f| headers.index(f) }.compact
            has_value = field_ixs.empty? || field_ixs.any? { |ix| (row[ix] || "").strip != "" }
            input = has_value ? render_template(spec["template"], headers, row) : ""
            if input != ""
              cached = GeocodeEntry.find_by(input: input)
              if cached
                result = { lat: cached.lat, lng: cached.lng }
                stats.from_cache += 1
              else
                fetched = geocoder.call(input)
                if fetched
                  # Cache hits and "not found"s, but not transient errors
                  result = fetched
                  GeocodeEntry.upsert({ input: input, lat: result[:lat], lng: result[:lng] }, unique_by: :input)
                end
                stats.fetched += 1
              end
            end
            if result[:lat].nil? && have_columns
              result = { lat: col_lat, lng: col_lng }
              stats.from_columns += 1
            elsif result[:lat].nil?
              stats.failed += 1
            end
          end

          out.write(CSV.generate_line(
            row + [ result[:lat]&.to_s || "", result[:lng]&.to_s || "" ], row_sep: "\r\n"
          ))
        end
      end
      stats
    end
  end
end
