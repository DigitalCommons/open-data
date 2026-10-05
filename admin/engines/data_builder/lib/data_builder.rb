require "data_builder/engine"

module DataBuilder
  # Where staged CSV uploads and built zips live.
  def self.storage_root
    Pathname.new(ENV.fetch("DATA_BUILDER_ROOT") { Rails.root.join("storage/data_builder").to_s })
  end

  def self.uploads_dir
    storage_root + "uploads"
  end

  def self.builds_dir
    storage_root + "builds"
  end

  UPLOAD_MAX_AGE = 24.hours

  # Drop staged uploads older than UPLOAD_MAX_AGE, sparing CSVs still
  # referenced by queued or running builds. Shared by CsvsController and
  # CleanupJob.
  def self.sweep_uploads!
    dir = uploads_dir
    FileUtils.mkdir_p(dir)
    cutoff = Time.current - UPLOAD_MAX_AGE
    keep = Build.where(status: %i[ queued running ]).pluck(:csv_id)
    dir.children.each do |f|
      next unless f.file? && f.mtime < cutoff
      next if keep.include?(f.basename.to_s[/\A\h{16}/])
      f.delete
    rescue Errno::ENOENT
      # raced with another sweep - ignore
    end
  end
end
