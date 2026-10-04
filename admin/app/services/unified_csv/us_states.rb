# US state names and USPS codes, for normalising the Region of US rows.
# Port of data-pipelines packages/dataset-build/src/us-states.ts.
module UnifiedCsv
  module UsStates
    CODES_BY_NAME = {
      "ALABAMA" => "AL", "ALASKA" => "AK", "ARIZONA" => "AZ", "ARKANSAS" => "AR",
      "CALIFORNIA" => "CA", "COLORADO" => "CO", "CONNECTICUT" => "CT", "DELAWARE" => "DE",
      "DISTRICT OF COLUMBIA" => "DC", "FLORIDA" => "FL", "GEORGIA" => "GA", "HAWAII" => "HI",
      "IDAHO" => "ID", "ILLINOIS" => "IL", "INDIANA" => "IN", "IOWA" => "IA",
      "KANSAS" => "KS", "KENTUCKY" => "KY", "LOUISIANA" => "LA", "MAINE" => "ME",
      "MARYLAND" => "MD", "MASSACHUSETTS" => "MA", "MICHIGAN" => "MI", "MINNESOTA" => "MN",
      "MISSISSIPPI" => "MS", "MISSOURI" => "MO", "MONTANA" => "MT", "NEBRASKA" => "NE",
      "NEVADA" => "NV", "NEW HAMPSHIRE" => "NH", "NEW JERSEY" => "NJ", "NEW MEXICO" => "NM",
      "NEW YORK" => "NY", "NORTH CAROLINA" => "NC", "NORTH DAKOTA" => "ND", "OHIO" => "OH",
      "OKLAHOMA" => "OK", "OREGON" => "OR", "PENNSYLVANIA" => "PA", "PUERTO RICO" => "PR",
      "RHODE ISLAND" => "RI", "SOUTH CAROLINA" => "SC", "SOUTH DAKOTA" => "SD", "TENNESSEE" => "TN",
      "TEXAS" => "TX", "UTAH" => "UT", "VERMONT" => "VT", "VIRGINIA" => "VA",
      "WASHINGTON" => "WA", "WEST VIRGINIA" => "WV", "WISCONSIN" => "WI", "WYOMING" => "WY"
    }.freeze
    CODES = Set.new(CODES_BY_NAME.values).freeze

    # A USPS code for a state name or code, or nil.
    def self.code(value)
      return nil if value.nil?
      v = Js.trim(value).sub(/\.\z/, "").upcase
      CODES.include?(v) ? v : CODES_BY_NAME[v]
    end

    # The state in a comma-separated address, searching from the end; a
    # trailing zip code in the same segment is allowed (e.g. "MN 55414").
    def self.from_address(address)
      return nil if address.nil?
      address.split(",", -1).reverse_each do |segment|
        state = code(segment.sub(/\s+\d{5}(-\d{4})?\s*\z/, ""))
        return state if state
      end
      nil
    end
  end
end
