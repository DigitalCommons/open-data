require "test_helper"

class DataSourcesControllerTest < ActionDispatch::IntegrationTest
  include OpenDataTestHelper

  setup do
    setup_open_data_env
    sign_in_as(users(:settled))
  end

  teardown { teardown_open_data_env }

  test "requires authentication" do
    sign_out
    get data_sources_path
    assert_redirected_to new_session_path
  end

  test "index lists sources with last download age" do
    get data_sources_path
    assert_response :success
    assert_select "h1", /Data sources/
    assert_select "td", /Alpha Co-ops/
    assert_select "td", /Beta Directory/
  end

  test "index groups sources under their projects, unassigned last" do
    get data_sources_path
    assert_response :success

    headings = css_select(".project-heading").map { |heading| heading.text.squish }
    assert_equal 3, headings.size
    assert_match(/\AProject: Cooperative World Map \(CWM\) MykoMaps v4 Co-operatives worldwide/, headings[0])
    assert_match(/\AProject: Mersey Green Network MykoMaps v3/, headings[1])
    assert_equal "Other sources", headings[2]

    assert_select "section#project_#{projects(:cwm).id} td", /Alpha Co-ops/
    assert_select "section#other_sources td", /Beta Directory/
    assert_select "section#project_#{projects(:mersey_green).id} td", /No data sources/
  end

  test "index links each project name, not its Project: label" do
    get data_sources_path
    assert_select ".project-heading a[href=?]", project_path(projects(:cwm)), text: "Cooperative World Map (CWM)"
    assert_select ".project-heading a", text: /Project:/, count: 0
  end

  test "index keeps the source controls" do
    get data_sources_path
    assert_select "form[action=?]", toggle_data_source_path(data_sources(:alpha))
    assert_select "form[action=?]", run_data_source_path(data_sources(:alpha))
    assert_select "a[href=?]", data_source_path(data_sources(:beta), anchor: "upload")
  end

  test "index has no Other sources group when every source has a project" do
    projects(:cwm).data_sources << data_sources(:beta)
    get data_sources_path
    assert_select "section#other_sources", count: 0
  end

  test "index lists a source under each of its projects" do
    projects(:mersey_green).data_sources << data_sources(:alpha)
    get data_sources_path
    assert_select "section#project_#{projects(:cwm).id} td", /Alpha Co-ops/
    assert_select "section#project_#{projects(:mersey_green).id} td", /Alpha Co-ops/
  end

  test "show links to each of the source's projects" do
    projects(:mersey_green).data_sources << data_sources(:alpha)
    get data_source_path(data_sources(:alpha))
    assert_select "dt", "Projects"
    assert_select "a[href=?]", project_path(projects(:cwm)), "Cooperative World Map (CWM)"
    assert_select "a[href=?]", project_path(projects(:mersey_green)), "Mersey Green Network"
  end

  test "index describes the page and ends with a summary" do
    get data_sources_path
    assert_select "p", "MykoMaps version 4 projects and data sources: download, schedules and unification."
    assert_select "th", "Status"
    assert_select "h2", "Summary"
    assert_operator response.body.index("id=\"other_sources\""), :<, response.body.index(">Summary<")
  end

  test "index shows a scheduled source with no schedule as unable to be enabled" do
    data_sources(:beta).update!(kind: :auto, schedule: nil)
    get data_sources_path
    assert_select "form[action=?] button[disabled]", toggle_data_source_path(data_sources(:beta))
    assert_select ".tog-hint", "Add a schedule to enable"
  end

  test "index shows upload-only sources without a switch" do
    get data_sources_path
    assert_select "form[action=?]", toggle_data_source_path(data_sources(:beta)), count: 0
    assert_select "td", "upload only"
  end

  test "show explains why a scheduled source with no schedule cannot be enabled" do
    beta = data_sources(:beta)
    beta.update!(kind: :auto, schedule: nil)
    get data_source_path(beta)
    assert_select ".flash", /This source has no schedule, so it cannot be enabled./
    assert_select ".flash a[href=?]", edit_data_source_path(beta), "Set a schedule"
    assert_select ".crumb a[href=?]", root_path, "Projects & Data Sources"
  end

  test "show displays the row ID note, or says it is not documented" do
    get data_source_path(data_sources(:alpha))
    assert_select "dt", "Row ID"
    assert_select "dd", "Not documented"
  end

  test "show displays details and run history" do
    get data_source_path(data_sources(:alpha))
    assert_response :success
    assert_select "h1", /Alpha Co-ops/
    assert_select "td", /scheduled/
  end

  test "show collapses all but the latest duplicate run behind a checkbox" do
    source = data_sources(:alpha)
    3.times do |i|
      source.download_runs.create!(status: :no_changes, triggered_by: :scheduled,
        started_at: (i + 1).hours.ago, finished_at: (i + 1).hours.ago, created_at: (i + 1).hours.ago)
    end

    get data_source_path(source)
    assert_response :success
    assert_select "tr.duplicate-run", count: 2
    assert_select "input[data-run-history-target=toggle]", count: 1
    assert_select "label", /Show history for all duplicate logs/
  end

  test "show has no duplicate checkbox when at most one no-change run" do
    get data_source_path(data_sources(:alpha))
    assert_select "input[data-run-history-target=toggle]", count: 0
  end

  test "update changes schedule and details" do
    patch data_source_path(data_sources(:alpha)), params: {
      data_source: { schedule: "0 4 * * *", description: "Nightly" }
    }
    assert_redirected_to data_source_path(data_sources(:alpha))
    assert_equal "0 4 * * *", data_sources(:alpha).reload.schedule
  end

  test "update rejects an invalid cron schedule" do
    patch data_source_path(data_sources(:alpha)), params: {
      data_source: { schedule: "nonsense" }
    }
    assert_response :unprocessable_entity
    assert_equal "*/10 * * * *", data_sources(:alpha).reload.schedule
  end

  test "toggle disables and re-enables a source" do
    post toggle_data_source_path(data_sources(:alpha))
    assert_not data_sources(:alpha).reload.enabled?

    post toggle_data_source_path(data_sources(:alpha))
    assert data_sources(:alpha).reload.enabled?
  end

  test "toggle cannot enable an auto source without a schedule" do
    source = data_sources(:beta)
    source.update!(kind: :auto, schedule: nil)
    post toggle_data_source_path(source)
    assert_not source.reload.enabled?
  end

  test "run queues a manual download" do
    assert_enqueued_with(job: DataSourceRunJob) do
      post run_data_source_path(data_sources(:alpha))
    end
    run = data_sources(:alpha).download_runs.order(:created_at).last
    assert run.queued?
    assert run.manual?
  end

  test "run refuses a manual-upload source" do
    assert_no_enqueued_jobs do
      post run_data_source_path(data_sources(:beta))
    end
    assert_redirected_to data_source_path(data_sources(:beta))
  end

  test "run refuses while a run is in progress" do
    data_sources(:alpha).download_runs.create!(status: :running, triggered_by: :manual)
    assert_no_enqueued_jobs do
      post run_data_source_path(data_sources(:alpha))
    end
  end

  test "upload stores the file and queues processing" do
    file = Rack::Test::UploadedFile.new(StringIO.new(default_csv), "text/csv",
      original_filename: "members.csv")

    assert_enqueued_with(job: DataSourceRunJob) do
      post upload_data_source_path(data_sources(:beta)), params: { file: file }
    end

    run = data_sources(:beta).download_runs.order(:created_at).last
    assert run.upload?
    assert_equal "members.csv", run.uploaded_filename
    assert File.file?(run.uploaded_file_path)
    assert_equal default_csv, File.read(run.uploaded_file_path)
  end

  test "upload without a file is rejected" do
    assert_no_enqueued_jobs do
      post upload_data_source_path(data_sources(:beta))
    end
    assert_redirected_to data_source_path(data_sources(:beta))
  end

  test "standard_csv downloads the latest converted output" do
    run = data_sources(:alpha).download_runs.succeeded.order(:created_at).last
    dir = OpenData.downloads_root + "alpha/2026-01-01_000000"
    FileUtils.mkdir_p(dir)
    File.write(dir + "standard.csv", default_csv)
    run.update!(archive_path: dir.to_s, started_at: Time.utc(2026, 10, 5, 6, 0, 12))

    get standard_csv_data_source_path(data_sources(:alpha))
    assert_response :success
    assert_equal default_csv, response.body
    assert_match(/filename="20261005-060012-alpha-standard\.csv"/, response.headers["Content-Disposition"])
  end

  test "standard_csv redirects when nothing has been converted" do
    DownloadRun.delete_all
    get standard_csv_data_source_path(data_sources(:alpha))
    assert_redirected_to data_source_path(data_sources(:alpha))
  end

  def archived_runs(count)
    source = data_sources(:alpha)
    source.download_runs.delete_all
    count.times.map do |i|
      at = Time.utc(2026, 9, 1) + i.days
      run = archive_standard_csv(source, "Identifier,Name\n#{(1..i + 1).map { |n| "#{n},Row #{n}" }.join("\n")}\n")
      run.update!(started_at: at, created_at: at, rows_added: 1, rows_removed: 0, rows_changed: 0,
        diff_summary: i.zero? ? "First download: 1 rows." : "1 added, 0 removed, 0 changed (#{i + 1} rows, was #{i}).")
      File.write(File.join(run.archive_path, "diff.txt"), "+ #{i + 1}: Row #{i + 1}\n")
      run
    end
  end

  test "show lists downloaded files newest first with their differences" do
    runs = archived_runs(3)
    get data_source_path(data_sources(:alpha))

    assert_select "h2", "Downloads"
    rows = css_select("#downloads tbody tr.download")
    assert_equal 3, rows.size
    assert_match(/2026-09-03/, rows.first.text)
    assert_select "#downloads a[href=?]", standard_csv_download_run_path(runs.last), "Download standard.csv"
    assert_select "#downloads td", /1 added, 0 removed, 0 changed \(3 rows, was 2\)/
    assert_select "#downloads td", "First download"
    assert_select "#downloads details summary", "Changed rows"
    assert_select "#downloads details pre", /\+ 3: Row 3/
    assert_select "#downloads td.num", "3"
  end

  test "show pages downloads 15 at a time" do
    archived_runs(16)
    get data_source_path(data_sources(:alpha))
    assert_select "#downloads tbody tr.download", 15
    assert_select "#downloads", /Page 1 of 2/
    assert_select "#downloads a", "Older"

    get data_source_path(data_sources(:alpha), downloads_page: 2)
    assert_select "#downloads tbody tr.download", 1
    assert_select "#downloads a", "Newer"
    assert_select "#downloads td", "First download"
  end

  test "show says when there are no downloads" do
    data_sources(:beta).download_runs.delete_all
    get data_source_path(data_sources(:beta))
    assert_select "#downloads td", "No downloads yet."
  end

  test "summary shows disk space used by downloads and builds in GB" do
    DiskUsage.create!(downloads_bytes: 1_300_000_000, builds_bytes: 200_000_000, measured_at: Time.current)
    get data_sources_path
    assert_select ".stat dt", "Disk space used"
    assert_select ".stat dd", "1.5 GB"
    assert_select "dl.summary.summary-five .stat", 5
  end

  test "summary shows a dash before disk space is first measured" do
    get data_sources_path
    assert_select ".stat dd", "-"
  end
end
