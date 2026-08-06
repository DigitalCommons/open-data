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
    assert_select "h1", /run ##{@run.id}/
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
    @run.update!(archive_path: dir.to_s)

    get standard_csv_download_run_path(@run)
    assert_response :success
    assert_equal default_csv, response.body

    get diff_download_run_path(@run)
    assert_response :success
    assert_equal "+ 1: One\n", response.body
  end
end
