require "csv"
require "se_open_data/config"
require "se_open_data/utils/password_store"
require_relative "mapbox_geocoder"
require_relative "standard_csv"

# The steps shared by converters that geocode with MapboxGeocoder and write
# a StandardCsv: read the config, build the geocoder, convert, write the
# output and report. Needs the se_open_data gem, so it is only loaded by
# converter scripts.
module ConverterSupport
  # Yields (input rows, geocoder) and expects [output rows, failures] back,
  # where failures are [name, reason] pairs. The geocode cache is saved even
  # when the block raises. Returns the exit status for the converter.
  def self.run(cache_path:, columns: StandardCsv::COLUMNS, **geocoder_options)
    config = SeOpenData::Config.load
    rows = CSV.read(File.join(config.SRC_CSV_DIR, config.ORIGINAL_CSV), headers: true).map(&:to_h)
    geocoder = MapboxGeocoder.new(cache: GeocodeCache.new(cache_path), token: mapbox_token(config),
                                  **geocoder_options)
    begin
      output, fails = yield rows, geocoder
    ensure
      geocoder.save
    end

    StandardCsv.write(config.STANDARD_CSV, output, columns: columns)
    puts "Wrote #{output.size} rows to #{config.STANDARD_CSV} " \
         "(#{geocoder.newly_geocoded} newly geocoded)"
    fails.each { |name, reason| warn "Not geocoded: #{name}: #{reason}" }
    return 0 unless geocoder.abort_reason

    warn "Geocoding stopped (#{geocoder.abort_reason}): set #{config.GEOCODER_API_KEY_PATH} " \
         "(PASSWORD__ environment variable or pass) to a valid Mapbox token"
    1
  end

  # nil when there is none, since cached queries need no token
  def self.mapbox_token(config)
    SeOpenData::Utils::PasswordStore.new(use_env_vars: config.USE_ENV_PASSWORDS)
      .get(config.GEOCODER_API_KEY_PATH)
  rescue RuntimeError => e
    warn "No Mapbox token, only cached geocodes can be used: #{e.message}"
    nil
  end
end
