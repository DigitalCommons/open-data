require "csv"
require "fileutils"

# Writes a standard.csv in the layout the data-pipelines transforms produce,
# which its clean-csv-data step reads by header name.
module StandardCsv
  COLUMNS = [
    "Identifier",
    "Name",
    "Description",
    "Organisational Structure",
    "Primary Activity",
    "Activities",
    "Street Address",
    "Locality",
    "Region",
    "Postcode",
    "Country ID",
    "Territory ID",
    "Website",
    "Phone",
    "Email",
    "Twitter",
    "Facebook",
    "Companies House Number",
    "Qualifiers",
    "Membership Type",
    "Latitude",
    "Longitude",
    "Geo Container",
    "Geo Container Confidence",
    "Geo Container Latitude",
    "Geo Container Longitude",
    "Geocoded Address",
    "Sector",
    "SIC Section",
    "SIC Code",
    "Ownership Classification",
    "Legal Form",
    "Domains",
    "Dataset",
  ].freeze

  # Country names seen in source data, mapped to ISO 3166-1 alpha-2 codes
  COUNTRY_IDS = {
    "USA" => "US",
    "United States" => "US",
    "UK" => "GB",
    "United Kingdom" => "GB",
    "Canada" => "CA",
    "Australia" => "AU",
  }.freeze

  # rows - hashes keyed by column name; missing columns are left empty
  def self.write(path, rows, columns: COLUMNS)
    rows.each do |row|
      unknown = row.keys - columns
      raise ArgumentError, "unknown columns: #{unknown.join(', ')}" unless unknown.empty?
    end

    text = CSV.generate do |csv|
      csv << columns
      rows.each do |row|
        # nil, not "", so empty values are written without quotes
        csv << columns.map { |column| row[column].to_s.empty? ? nil : row[column] }
      end
    end

    # Like data-pipelines (json2csv): no trailing newline, except after a
    # header with no rows
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, rows.empty? ? text : text.chomp)
  end
end
