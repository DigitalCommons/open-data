# The latest measurement of the space taken by downloaded and built files
# (see DiskUsageJob). Only one row is kept.
class DiskUsage < ApplicationRecord
  def self.latest
    order(:measured_at).last
  end

  def self.record!(downloads_bytes:, builds_bytes:)
    usage = latest || new
    usage.update!(downloads_bytes: downloads_bytes, builds_bytes: builds_bytes, measured_at: Time.current)
    where.not(id: usage.id).delete_all
    usage
  end

  def total_bytes
    downloads_bytes + builds_bytes
  end
end
