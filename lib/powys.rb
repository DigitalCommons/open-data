require "csv"
require "json"
require_relative "mapbox_geocoder"

# Maps the Powys Food Map sheet to one CSV per language, shared by the
# powys-eng and powys-cym sources.
#
# Categories and localities are matched on the sheet's English names
# (Category, Subcategory, Town), not its ID columns, against
# powys/vocabs.json: the English fsc and loc terms copied from the
# data-pipelines powys-data MykoMap config. Sub-category labels there
# start with " - ".
module Powys
  DIR = File.join(__dir__, "powys")
  CACHE_PATH = File.join(DIR, "geocodes.csv")

  # Restricts Mapbox to the Powys area. Preferring the postcode feature
  # gets the right location where street names are ambiguous.
  GEOCODER_OPTIONS = { bbox: [-5.4, 51.35, -2.6, 53.53], prefer_feature_type: "postcode" }.freeze

  # Sheet columns holding the name and description in each language
  LANGUAGES = {
    "eng" => ["Title_Eng", "Text for popup"],
    "cym" => ["Title_Cym", "Text for popup_Cym"],
  }.freeze

  # The headers the Powys MykoMap configs read (itemProps `from`)
  COLUMNS = [
    "Identifier",
    "Name",
    "Description",
    "Street Address",
    "Website",
    "Primary Food System Category ID",
    "Food System Category IDs",
    "Locality ID",
    "Geo Container Latitude",
    "Geo Container Longitude",
    "Geo Container Confidence",
    "Geocoded Address",
    "Contact name",
    "Email address",
    "Phone number",
  ].freeze

  # Not a real confidence: the MykoMap config expects a value
  CONFIDENCE = "51".freeze

  # The first line of the sheet is notes, the headers are on the second.
  # Empty fields are read as "", not nil.
  def self.read(text)
    CSV.parse(text.lines.drop(1).join, headers: true, nil_value: "").map(&:to_h)
       .reject { |row| row["ID"].to_s.empty? }
  end

  def self.vocabs(path = File.join(DIR, "vocabs.json"))
    JSON.parse(File.read(path))
  end

  def self.query(row)
    "#{row['Address'].gsub("\n", ', ')}, #{row['Postcode']}, GB"
  end

  # Returns [rows sorted by name, [[name, reason], ...] for rows that could
  # not be geocoded]. Those rows are kept, without coordinates.
  def self.convert(rows, geocoder, vocabs, language)
    name_column, description_column = LANGUAGES.fetch(language)
    categories = vocabs.fetch("fsc")
    localities = vocabs.fetch("loc")
    fails = []

    output = rows.map do |row|
      lat, lng, geocoded_address = locate(row, geocoder, fails)
      primary = categories.key(row["Category"])
      {
        "Identifier" => row["ID"],
        "Name" => row[name_column].delete("\r\n"),
        "Description" => row[description_column].delete("\r"),
        "Street Address" => row["Address"].delete("\r"),
        "Website" => row["Link"],
        "Primary Food System Category ID" => primary,
        "Food System Category IDs" => [primary, categories.key(" - #{row['Subcategory']}")].join(";"),
        "Locality ID" => localities.key(row["Town"]),
        "Geo Container Latitude" => lat,
        "Geo Container Longitude" => lng,
        "Geo Container Confidence" => CONFIDENCE,
        "Geocoded Address" => geocoded_address,
        "Contact name" => row["Contact name"],
        "Email address" => row["Email address"],
        "Phone number" => row["Phone number"],
      }
    end
    [output.each_with_index.sort_by { |item, index| [item["Name"], index] }.map(&:first), fails]
  end

  # Coordinates in the sheet's Geocode column ("lat, lng") win over
  # geocoding. Returns [lat, lng, geocoded address].
  #
  # For those rows the geocoded address is the text "undefined", matching
  # the data-pipelines output, which writes a JavaScript undefined there.
  def self.locate(row, geocoder, fails)
    unless row["Geocode"].to_s.empty?
      lat, lng = row["Geocode"].split(", ")
      return [number(lat), number(lng), "undefined"]
    end

    geocoded = geocoder.geocode(query(row))
    if geocoded.is_a?(MapboxGeocoder::Failure)
      fails << [row["Title_Eng"], geocoded.reason]
      return [nil, nil, nil]
    end
    [number(geocoded.lat), number(geocoded.lng), geocoded.geocoded_address]
  end

  # Like JavaScript's String(parseFloat(text))
  def self.number(text)
    value = text.to_s[/\A\s*[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?/]
    value && MapboxGeocoder.format_coordinate(Float(value))
  end
end
