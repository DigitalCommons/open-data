module DataBuilder
  # Cached geocode results, shared across builds. Failures are cached too
  # (nil lat/lng) so rebuilds don't re-hit the geocoder.
  class GeocodeEntry < ApplicationRecord
    self.table_name = "mykomap_geocode_entries"

    validates :input, presence: true, uniqueness: true
  end
end
