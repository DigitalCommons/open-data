# Names a downloaded file by when it was made (UTC) and what it belongs to,
# e.g. 20261005-060012-workers-coop-standard.csv.
module DownloadFilename
  def self.for(time, name, file)
    "#{time.utc.strftime('%Y%m%d-%H%M%S')}-#{name}-#{file}"
  end
end
