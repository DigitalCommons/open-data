require "test_helper"

class DownloadRunsControllerTest < ActionDispatch::IntegrationTest
  include OpenDataTestHelper

  setup do
    setup_open_data_env
    sign_in_as(users(:settled))
    @run = download_runs(:alpha_success)
  end

  teardown { teardown_open_data_env }

  test "requires authentication" do
    sign_out
    get download_run_path(@run)
    assert_redirected_to new_session_path
  end

  test "show renders log and diff summary" do
    get download_run_path(@run)
    assert_response :success
    assert_select "h1", "Run ##{@run.id}"
    assert_select ".crumb a[href=?]", data_source_path(@run.data_source)
    assert_select "p", /2 added, 1 removed, 3 changed/
  end

  test "standard_csv and diff redirect when not archived" do
    get standard_csv_download_run_path(@run)
    assert_redirected_to download_run_path(@run)

    get diff_download_run_path(@run)
    assert_redirected_to download_run_path(@run)
  end

  test "standard_csv and diff download archived files" do
    dir = OpenData.downloads_root + "alpha/2026-01-01_000000"
    FileUtils.mkdir_p(dir)
    File.write(dir + "standard.csv", default_csv)
    File.write(dir + "diff.txt", "+ 1: One\n")
    @run.update!(archive_path: dir.to_s, started_at: Time.utc(2026, 10, 5, 6, 0, 12))

    get standard_csv_download_run_path(@run)
    assert_response :success
    assert_equal default_csv, response.body
    assert_match(/filename="20261005-060012-alpha-standard\.csv"/, response.headers["Content-Disposition"])

    get diff_download_run_path(@run)
    assert_response :success
    assert_equal "+ 1: One\n", response.body
    assert_match(/filename="20261005-060012-alpha-diff\.txt"/, response.headers["Content-Disposition"])
  end
end
