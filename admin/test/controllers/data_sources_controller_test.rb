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
    data_sources(:beta).update!(project: projects(:cwm))
    get data_sources_path
    assert_select "section#other_sources", count: 0
  end

  test "show links to the source's project" do
    get data_source_path(data_sources(:alpha))
    assert_select "a[href=?]", project_path(projects(:cwm)), "Cooperative World Map (CWM)"
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
    run.update!(archive_path: dir.to_s)

    get standard_csv_data_source_path(data_sources(:alpha))
    assert_response :success
    assert_equal default_csv, response.body
    assert_match(/alpha-standard\.csv/, response.headers["Content-Disposition"])
  end

  test "standard_csv redirects when nothing has been converted" do
    DownloadRun.delete_all
    get standard_csv_data_source_path(data_sources(:alpha))
    assert_redirected_to data_source_path(data_sources(:alpha))
  end
end
