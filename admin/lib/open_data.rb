# Locates the surrounding open-data repo and the download archive area.
module OpenData
  def self.root
    Pathname.new(ENV.fetch("OPEN_DATA_ROOT") { Rails.root.join("..").to_s }).expand_path
  end

  def self.downloads_root
    Pathname.new(ENV.fetch("DOWNLOADS_ROOT") { Rails.root.join("storage/downloads").to_s }).expand_path
  end

  # Prefix for invoking seod inside a project dir. Empty string means run
  # `seod` directly (used by the test suite, which puts a stub on PATH).
  def self.seod_wrapper
    ENV.fetch("SEOD_WRAPPER", "bundle exec")
  end

  # Project directories: those containing a `converter` script.
  def self.project_directories
    root.children.select { |d| d.directory? && (d + "converter").file? }.map { |d| d.basename.to_s }.sort
  end
end
