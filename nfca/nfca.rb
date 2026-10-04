require_relative "../lib/mapbox_geocoder"
require_relative "../lib/standard_csv"

# Maps NFCA Food Coop Network rows (a HubSpot export) to standard.csv rows.
module Nfca
  # NFCA "Co-op Sector" (lower case) to ICA activity codes, see
  # https://dev.vocabs.digitalcommons.coop/essglobal/2.1/html-content/essglobal.html#H4
  ACTIVITIES = { "retail" => "ICA240" }.freeze

  # The data-unification global IDs are built from this, so it must not change
  def self.slugify(name)
    name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
  end

  def self.street(row)
    [row["Street Address"], row["Street Address 2"]].reject { |part| part.to_s.empty? }.join(", ")
  end

  def self.query(row)
    MapboxGeocoder.query([street(row), row["City"], row["State/Region"], row["Country/Region"]])
  end

  # Returns [standard rows, [[name, reason], ...] for rows dropped because
  # they failed to geocode]. Stops at the first failure that aborts geocoding.
  def self.convert(rows, geocoder)
    output = []
    fails = []
    rows.reject { |row| row["Company name"].start_with?("Example") }.each do |row|
      geocoded = geocoder.geocode(query(row))
      if geocoded.is_a?(MapboxGeocoder::Failure)
        fails << [row["Company name"], geocoded.reason]
        break if geocoded.abort

        next
      end
      output << standard_row(row, geocoded)
    end
    [output, fails]
  end

  def self.standard_row(row, geocoded)
    sector = row["Co-op Sector"]
    activity = ACTIVITIES[sector.downcase] or
      raise ArgumentError, "Unmapped Co-op Sector: #{sector}. Add it to Nfca::ACTIVITIES."
    country = row["Country/Region"].strip

    {
      "Identifier" => slugify(row["Company name"]),
      "Name" => row["Company name"],
      "Primary Activity" => activity,
      "Street Address" => street(row),
      "Locality" => row["City"],
      "Region" => row["State/Region"],
      "Country ID" => StandardCsv::COUNTRY_IDS.fetch(country, country),
      "Website" => row["Company Domain Name (If known)"],
      "Latitude" => geocoded.lat,
      "Longitude" => geocoded.lng,
      "Geocoded Address" => geocoded.geocoded_address,
      "Sector" => sector,
      "Dataset" => "nfca",
    }
  end
end
