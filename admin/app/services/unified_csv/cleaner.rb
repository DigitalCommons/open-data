require "csv"

# Cleans one source's standard.csv for unification. A port of data-pipelines
# packages/dataset-build/src/scripts/clean-csv-data.ts, kept faithful so the
# unified CSV matches what data-pipelines produces; see that script for the
# reasons behind each rule. Per row, in order:
#
# - logs an error if Country ID is empty
# - empties an Organisational Structure that is not a known OS term
# - derives Domains (when empty) from the registrable domains of Website
# - empties Website for DotCoop (dc), which lists domains there
# - strips vocab URI prefixes, trims text fields, and normalises US
#   regions to USPS codes
# - prefixes workers.coop (wc) and DotCoop (dc) vocab keys
#
# Output columns are the input's, then Domains (if absent), then Dataset
# (the table code). Rows failing the table's row filter are dropped.
module UnifiedCsv
  class Cleaner
    ORGANISATIONAL_STRUCTURES = Set.new(%w[
      OS10 OS110 OS115 OS120 OS130 OS140 OS160 OS170 OS180 OS190 OS200
      OS210 OS230 OS240 OS40 OS50
    ]).freeze

    VOCAB_FIELDS = [ "Primary Activity", "Organisational Structure", "Membership Type",
                     "Qualifiers", "Country ID", "Activities" ].freeze
    TRIMMED_FIELDS = [ "Identifier", "Name", "Description", "Street Address",
                       "Locality", "Region", "Postcode" ].freeze
    WC_PREFIXES = { "Registered Status" => "RS", "Industry" => "IND",
                    "Ownership Classification" => "OT", "Legal Form" => "LF" }.freeze
    DC_PREFIXES = { "Economic Sector ID" => "ES", "Organisational Category ID" => "OC" }.freeze

    # log receives one hash per entry, with the keys of the data-pipelines
    # TSV log: dataset_id, id, type, message, url, domain.
    def initialize(code:, row_filter: {}, log: [])
      @code = code
      @row_filter = row_filter
      @log = log
    end

    # Cleans input_path into output_path; returns the number of rows written.
    def clean(input_path, output_path)
      count = 0
      CSV.open(output_path, "w", quote_empty: false) do |out|
        columns = nil
        CSV.foreach(input_path, encoding: "UTF-8") do |values|
          values = values.map(&:to_s)
          if columns.nil?
            columns = (values - [ "Dataset" ]) | [ "Domains", "Dataset" ]
            @input_columns = values
            out << columns
            next
          end
          row = to_row(values)
          next unless passes_filter?(row)
          out << transform(row).values_at(*columns)
          count += 1
        end
      end
      count
    end

    private

    def to_row(values)
      row = {}
      @input_columns.each_with_index { |column, index| row[column] = values[index] || "" }
      row["Dataset"] = @code
      row
    end

    def passes_filter?(row)
      @row_filter.all? { |column, value| row[column] == value }
    end

    def transform(row)
      common = { dataset_id: row["Dataset"], id: row["Identifier"] }

      if row["Country ID"].blank?
        log(common, type: "error", message: "no value of #{'Country ID'.to_json}")
      end

      os = row["Organisational Structure"]&.sub(/.*\//, "")
      if os.present? && !ORGANISATIONAL_STRUCTURES.include?(os)
        log(common, type: "error", message: "unsupported Organisational Structure term, zapping: #{os.to_json}")
        row["Organisational Structure"] = nil
      end

      row["Website"] = nil if row["Website"] == ""
      row["Domains"] = nil if row["Domains"] == ""
      row["Domains"] = derive_domains(row["Website"], common) if row["Domains"].nil? && !row["Website"].nil?

      row["Website"] = nil if @code == "dc"

      VOCAB_FIELDS.each do |field|
        row[field] = row[field].gsub(/https?:[^;]*\//i, "") unless row[field].nil?
      end

      TRIMMED_FIELDS.each do |field|
        row[field] = Js.trim(row[field]) unless row[field].nil?
      end

      if row["Country ID"]&.match?(/\Ausa?\z/i)
        row["Region"] = UsStates.code(row["Region"]) || UsStates.from_address(row["Geocoded Address"]) || row["Region"]
      end

      prefix_vocab_keys(row, WC_PREFIXES) if @code == "wc"
      if @code == "dc"
        prefix_vocab_keys(row, DC_PREFIXES) { |value| value.include?(":") ? value.split(":", -1).last : value }
        row["Country ID"] = row["Country ID"].downcase if row["Country ID"].present?
      end

      row
    end

    def prefix_vocab_keys(row, prefixes)
      prefixes.each do |field, prefix|
        value = row[field]
        next if value.nil? || value == ""
        row[field] = prefix + (block_given? ? yield(value) : value)
      end
    end

    # Registrable domains of the ';'-separated website URLs, sorted and
    # ';'-joined. Parts with a path, no ICANN suffix or a blacklisted domain
    # are skipped unless whitelisted.
    def derive_domains(website, common)
      domains = []
      website.split(";", -1).each do |part|
        if part.match?(/[ ,]/)
          log(common, type: "error", message: "invalid url", url: part)
          next
        end
        part = "http://#{part}" if part.match?(/./) && !part.start_with?("http")

        url = WebUrl.parse(part)
        if url.nil?
          log(common, type: "error", message: "invalid url", url: part)
          next
        end

        domain, icann = registrable_domain(url.host)
        if domain && DomainLists::WHITELIST.include?(domain)
          log(common, type: "info", message: "including whitelisted domain", url: part, domain: domain)
          domains << domain unless domains.include?(domain)
        elsif url.path.length > 1
          log(common, type: "error", message: "url must not have path", url: part, domain: domain)
        elsif !icann
          log(common, type: "error", message: "non-icann domain", url: part, domain: domain)
        elsif domain && DomainLists::BLACKLIST.include?(domain)
          log(common, type: "info", message: "excluding blacklisted domain", url: part, domain: domain)
        else
          domains << domain unless domains.include?(domain)
        end
      end
      # JavaScript sorts null as the string "null" and joins it as ""
      domains.sort_by { |domain| domain || "null" }.map(&:to_s).join(";")
    end

    # [registrable domain, whether an ICANN suffix rule matched], as tldts
    # reports them with private suffixes ignored. IP addresses have neither.
    def registrable_domain(host)
      return [ nil, false ] if host.start_with?("[") || host.match?(/\A\d+(\.\d+){3}\z/)
      icann = !PublicSuffix::List.default.find(host, default: nil, ignore_private: true).nil?
      [ PublicSuffix.domain(host, ignore_private: true), icann ]
    end

    def log(common, type:, message:, url: nil, domain: nil)
      @log << common.merge(type: type, message: message, url: url, domain: domain)
    end
  end
end
