require "test_helper"

class DownloadRunTest < ActiveSupport::TestCase
  test "duration" do
    run = download_runs(:alpha_success)
    assert_in_delta 30.0, run.duration, 0.1
    assert_nil DownloadRun.new.duration
  end

  test "changes?" do
    assert download_runs(:alpha_success).changes?
    run = DownloadRun.new(rows_added: 0, rows_removed: 0, rows_changed: 0)
    assert_not run.changes?
    assert_not DownloadRun.new.changes?
  end

  test "archive paths are nil without an archive or file" do
    run = download_runs(:alpha_success)
    assert_nil run.standard_csv_path
    assert_nil run.diff_path

    Dir.mktmpdir do |dir|
      run.archive_path = dir
      assert_nil run.standard_csv_path
      File.write(File.join(dir, "standard.csv"), "Identifier\n")
      assert_equal File.join(dir, "standard.csv"), run.standard_csv_path
    end
  end

  test "append_log concatenates" do
    run = DownloadRun.new
    run.append_log("one\n")
    run.append_log("two\n")
    assert_equal "one\ntwo\n", run.log
  end

  test "completed scope covers succeeded and no_changes" do
    assert_includes DownloadRun.completed, download_runs(:alpha_success)
    assert_not_includes DownloadRun.completed, download_runs(:alpha_failed)
  end

  test "row_count is counted from the archived standard.csv once and remembered" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "standard.csv"), "Identifier,Name\n1,One\n2,\"Two\nlines\"\n")
      run = download_runs(:alpha_success)
      run.update!(archive_path: dir, row_count: nil)
      assert_equal 2, run.archived_row_count
      assert_equal 2, run.reload.row_count
    end
  end

  test "download_filename is the start time in UTC, source and file" do
    run = download_runs(:alpha_success)
    run.started_at = Time.utc(2026, 10, 5, 6, 0, 12)
    assert_equal "20261005-060012-alpha-standard.csv", run.download_filename("standard.csv")
  end
end
