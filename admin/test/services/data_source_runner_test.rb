require "test_helper"

class DataSourceRunnerTest < ActiveSupport::TestCase
  include OpenDataTestHelper

  setup do
    setup_open_data_env
    @source = data_sources(:alpha)
    @source.download_runs.destroy_all
    create_source_dir("alpha")
  end

  teardown { teardown_open_data_env }

  def new_run(attrs = {})
    @source.download_runs.create!({ status: :queued, triggered_by: :manual }.merge(attrs))
  end

  test "successful run downloads, converts, archives and diffs" do
    run = DataSourceRunner.new(new_run).call

    assert run.succeeded?, "expected success, log: #{run.log}"
    assert run.started_at && run.finished_at
    assert_equal 0, run.exit_code
    assert_match(/stub: downloading/, run.log)
    assert_match(/stub: converting/, run.log)

    assert File.file?(run.standard_csv_path)
    assert File.file?(run.diff_path)
    assert File.file?(File.join(run.archive_path, "meta.json"))
    assert File.file?(File.join(run.archive_path, "original/original.csv"))

    assert_equal 2, run.rows_added
    assert_match(/First download: 2 rows/, run.diff_summary)
  end

  test "second run diffs against the previous archive" do
    DataSourceRunner.new(new_run).call

    File.write(OpenData.root + "alpha/next-download.csv", <<~CSV)
      Identifier,Name,Website
      1,One,https://one.example.com
      2,Two renamed,https://two.example.com
      3,Three,https://three.example.com
    CSV
    run = DataSourceRunner.new(new_run).call

    assert run.succeeded?, "log: #{run.log}"
    assert_equal 1, run.rows_added
    assert_equal 0, run.rows_removed
    assert_equal 1, run.rows_changed
    assert_match(/~ 2: Name/, File.read(run.diff_path))
  end

  test "identical re-download records no_changes and discards the archive" do
    first = DataSourceRunner.new(new_run).call
    assert first.succeeded?

    run = DataSourceRunner.new(new_run).call

    assert run.no_changes?, "log: #{run.log}"
    assert_nil run.archive_path
    assert_match(/identical to previous download/, run.log)
    assert_equal 1, Dir.children(OpenData.downloads_root + "alpha").size,
      "duplicate archive should have been removed"
  end

  test "exit 100 records no_changes without archiving" do
    ENV["SEOD_STUB_DOWNLOAD_EXIT"] = "100"
    run = DataSourceRunner.new(new_run).call

    assert run.no_changes?
    assert_equal 100, run.exit_code
    assert_nil run.archive_path
    assert_match(/No new data available/, run.log)
  end

  test "download failure records failed with log" do
    ENV["SEOD_STUB_DOWNLOAD_EXIT"] = "3"
    run = DataSourceRunner.new(new_run).call

    assert run.failed?
    assert_equal 3, run.exit_code
    assert_nil run.archive_path
  end

  test "convert failure records failed" do
    ENV["SEOD_STUB_CONVERT_EXIT"] = "2"
    run = DataSourceRunner.new(new_run).call

    assert run.failed?
    assert_equal 2, run.exit_code
  end

  test "missing source directory fails cleanly" do
    @source.update!(directory: "gone", schedule: @source.schedule)
    run = DataSourceRunner.new(new_run).call

    assert run.failed?
    assert_match(/Source directory not found/, run.log)
  end

  test "upload run installs the file and skips the download step" do
    upload = OpenData.downloads_root + "alpha/incoming/upload.csv"
    FileUtils.mkdir_p(upload.dirname)
    File.write(upload, default_csv)

    run = DataSourceRunner.new(new_run(triggered_by: :upload,
      uploaded_filename: "original.csv", uploaded_file_path: upload.to_s)).call

    assert run.succeeded?, "log: #{run.log}"
    assert_no_match(/stub: downloading/, run.log)
    assert_match(/Installed uploaded file/, run.log)
    assert File.file?(OpenData.root + "alpha/original-data/original.csv")
    assert_equal 2, run.rows_added
  end

  test "subprocess_env scrubs bundler leakage but keeps other PATH entries" do
    vendored_bin = File.join(Bundler.bundle_path.to_s, "ruby/3.2.0/bin")
    ENV["PATH"] = "#{vendored_bin}:#{ENV['PATH']}"
    ENV["BUNDLER_VERSION"] = "4.0.10"
    ENV["BUNDLE_GEMFILE"] = "/somewhere/Gemfile"
    ENV["GEM_HOME"] = "/somewhere/gems"
    ENV["RUBYOPT"] = "-rbundler/setup"

    env = DataSourceRunner.new(new_run).send(:subprocess_env)

    assert_nil env["BUNDLER_VERSION"]
    assert_nil env["BUNDLE_GEMFILE"]
    assert_nil env["GEM_HOME"]
    assert_nil env["RUBYOPT"]
    path_entries = env["PATH"].split(File::PATH_SEPARATOR)
    assert_not_includes path_entries, vendored_bin
    assert_includes path_entries, OpenDataTestHelper::STUB_BIN
  ensure
    ENV.delete("BUNDLER_VERSION")
    ENV.delete("GEM_HOME")
    ENV.delete("RUBYOPT")
  end

  test "upload run with a missing file fails" do
    run = DataSourceRunner.new(new_run(triggered_by: :upload,
      uploaded_filename: "x.csv", uploaded_file_path: "/nonexistent/x.csv")).call

    assert run.failed?
    assert_match(/Uploaded file missing/, run.log)
  end
end
