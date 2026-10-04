require "tmpdir"

# Points OpenData at a throwaway repo/downloads root and puts the stub seod
# on PATH. Include in tests that touch the pipeline or the filesystem.
module OpenDataTestHelper
  STUB_BIN = File.expand_path("../stub_bin", __dir__)

  def setup_open_data_env
    @open_data_tmp = Dir.mktmpdir("open-data-test")
    @saved_env = ENV.to_h.slice("OPEN_DATA_ROOT", "DOWNLOADS_ROOT", "SEOD_WRAPPER", "PATH", "BUILDS_ROOT",
      "SEOD_STUB_DOWNLOAD_EXIT", "SEOD_STUB_CONVERT_EXIT")
    ENV["OPEN_DATA_ROOT"] = File.join(@open_data_tmp, "repo")
    ENV["DOWNLOADS_ROOT"] = File.join(@open_data_tmp, "downloads")
    ENV["BUILDS_ROOT"] = File.join(@open_data_tmp, "builds")
    ENV["SEOD_WRAPPER"] = ""
    ENV["PATH"] = "#{STUB_BIN}:#{ENV['PATH']}"
    FileUtils.mkdir_p(ENV["OPEN_DATA_ROOT"])
  end

  def teardown_open_data_env
    %w[ OPEN_DATA_ROOT DOWNLOADS_ROOT BUILDS_ROOT SEOD_WRAPPER PATH SEOD_STUB_DOWNLOAD_EXIT SEOD_STUB_CONVERT_EXIT ].each do |key|
      @saved_env.key?(key) ? ENV[key] = @saved_env[key] : ENV.delete(key)
    end
    FileUtils.remove_entry(@open_data_tmp) if @open_data_tmp
  end

  # Creates a fixture source dir with a queued next-download.csv.
  def create_source_dir(directory, csv: default_csv)
    dir = OpenData.root + directory
    FileUtils.mkdir_p(dir)
    File.write(dir + "converter", "#!/bin/sh\n")
    File.write(dir + "next-download.csv", csv)
    dir
  end

  # Gives the source a succeeded run whose archive holds this standard.csv.
  def archive_standard_csv(source, csv)
    dir = OpenData.downloads_root + source.directory + "2026-01-01_000000-#{SecureRandom.hex(3)}"
    FileUtils.mkdir_p(dir)
    File.write(dir + "standard.csv", csv)
    source.download_runs.create!(status: :succeeded, triggered_by: :scheduled,
      started_at: 1.minute.ago, finished_at: Time.current, archive_path: dir.to_s)
  end

  def default_csv
    <<~CSV
      Identifier,Name,Website
      1,One,https://one.example.com
      2,Two,https://two.example.com
    CSV
  end
end
