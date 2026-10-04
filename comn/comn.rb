require "json"
require_relative "../lib/mapbox_geocoder"
require_relative "../lib/standard_csv"

# Maps Co-Minnesota (APEX) sheet rows to standard.csv rows.
#
# Organisational Structure, Membership Type, Activities and Country/Region
# hold English vocab term labels (the sheet template's dropdowns). They are
# looked up in vocabs.json, the English terms of the aci, os, bmt and coun
# vocabs copied from data-pipelines packages/dataset-build/mykomap/base.json.
module Comn
  VOCABS_URL = "https://dev.vocabs.digitalcommons.coop/essglobal/2.1/html-content/essglobal.html".freeze

  VOCAB_COLUMNS = {
    "aci" => "Activities",
    "os" => "Organisational Structure",
    "bmt" => "Membership Type",
    "coun" => "Country/Region",
  }.freeze

  # Returns { vocab => { lower case label => code } }
  def self.vocabs(path = File.join(__dir__, "vocabs.json"))
    JSON.parse(File.read(path)).transform_values do |terms|
      terms.to_h { |code, label| [label.downcase, code] }
    end
  end

  # Returns [standard rows, [[title, reason], ...] for rows dropped because
  # they failed to geocode]. Stops at the first failure that aborts geocoding.
  def self.convert(rows, geocoder, vocabs)
    rows = rows.select { |row| present?(row["ID"]) || present?(row["Title"]) }
    check_ids(rows)

    output = []
    fails = []
    rows.each do |row|
      # Comma separated in the template; some data uses semicolons
      activities = row["Activities"].to_s.split(/[,;]/).map(&:strip).reject(&:empty?)
                                    .map { |label| term(vocabs, "aci", label, row) }
      structure = term(vocabs, "os", row["Organisational Structure"], row)
      membership = term(vocabs, "bmt", row["Membership Type"], row)

      geocoded = locate(row, geocoder)
      if geocoded.is_a?(MapboxGeocoder::Failure)
        fails << [row["Title"].to_s.strip, geocoded.reason]
        break if geocoded.abort

        next
      end

      output << {
        "Identifier" => row["ID"].strip,
        "Name" => row["Title"].strip,
        "Description" => row["Text for popup"],
        "Organisational Structure" => structure,
        "Primary Activity" => activities.first,
        "Activities" => activities.join(";"),
        "Street Address" => MapboxGeocoder.query([row["Street Address"], row["Street Address 2"]]),
        "Locality" => row["City"],
        "Region" => row["State/Region"],
        "Postcode" => row["Postcode/Zip"],
        "Country ID" => country_id(vocabs, row),
        # Several URLs may be given, separated by ;
        "Website" => row["Website URL"].to_s.split(";").map(&:strip).reject(&:empty?).join(";"),
        "Phone" => row["Phone number"],
        "Email" => row["Email address"],
        "Membership Type" => membership,
        "Latitude" => geocoded.lat,
        "Longitude" => geocoded.lng,
        "Geocoded Address" => geocoded.geocoded_address,
        "Dataset" => "comn",
      }
    end
    [output, fails]
  end

  def self.present?(value)
    !value.to_s.strip.empty?
  end

  # The ID is the permanent Identifier, so map links survive renames
  def self.check_ids(rows)
    seen = {}
    rows.each do |row|
      id = row["ID"].to_s.strip
      unless id.match?(/\A[A-Za-z0-9._-]+\z/)
        raise ArgumentError, "Invalid ID #{row['ID'].inspect} for row titled #{row['Title'].inspect}: " \
                             "every row needs a unique ID (letters, digits, . _ - only)"
      end
      if seen.key?(id)
        raise ArgumentError, "Duplicate ID #{id}: used by both #{seen[id].inspect} and #{row['Title'].inspect}"
      end

      seen[id] = row["Title"]
    end
  end

  def self.term(vocabs, vocab, label, row)
    label = label.to_s.strip
    return "" if label.empty?

    vocabs.fetch(vocab)[label.downcase] or
      raise ArgumentError, "Unrecognised #{VOCAB_COLUMNS[vocab]} value #{label.inspect} in row ID " \
                           "#{row['ID']} (#{row['Title']}). It must exactly match an English term " \
                           "label of the \"#{vocab}\" vocab in vocabs.json (see also #{VOCABS_URL})"
  end

  def self.country_id(vocabs, row)
    country = row["Country/Region"].to_s.strip
    StandardCsv::COUNTRY_IDS[country] || term(vocabs, "coun", country, row).upcase
  end

  # Coordinates in the sheet are used as they are, with the address from
  # the sheet as the geocoded address; otherwise the address is geocoded
  def self.locate(row, geocoder)
    lat = row["Latitude"].to_s.strip
    lng = row["Longitude"].to_s.strip
    address = [row["Street Address"], row["Street Address 2"], row["City"],
               row["State/Region"], row["Postcode/Zip"], row["Country/Region"]]
    return geocoder.geocode(MapboxGeocoder.query(address)) if lat.empty? || lng.empty?

    unless Float(lat, exception: false) && Float(lng, exception: false)
      raise ArgumentError, "Invalid Latitude/Longitude (#{lat.inspect}, #{lng.inspect}) " \
                           "in row ID #{row['ID']} (#{row['Title']})"
    end
    MapboxGeocoder::Result.new(lat, lng, MapboxGeocoder.query(address), true)
  end
end
