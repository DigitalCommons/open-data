require "open3"

# Measures the downloads and builds folders with `du`, which is much faster
# than walking the files in Ruby. Runs hourly (config/recurring.yml) and
# after each build.
class DiskUsageJob < ApplicationJob
  queue_as :default

  def perform
    DiskUsage.record!(downloads_bytes: bytes(OpenData.downloads_root), builds_bytes: bytes(OpenData.builds_root))
  end

  private

  # Apparent size in bytes; 0 when the folder does not exist yet.
  def bytes(path)
    return 0 unless path.directory?
    output, status = Open3.capture2("du", "-sb", path.to_s)
    status.success? ? output.to_i : 0
  end
end
