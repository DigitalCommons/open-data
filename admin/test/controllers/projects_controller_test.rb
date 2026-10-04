require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:settled)) }

  test "requires authentication" do
    sign_out
    get project_path(projects(:cwm))
    assert_redirected_to new_session_path
  end

  test "show displays description, category and linked sources" do
    get project_path(projects(:cwm))
    assert_response :success
    assert_select "h1", /Cooperative World Map/
    assert_select "span", "MykoMaps v4"
    assert_select "dd", /Co-operatives worldwide/
    assert_select "a[href=?]", data_source_path(data_sources(:alpha)), /Alpha Co-ops/
    assert_select "a[href=?]", edit_project_path(projects(:cwm)), "Edit"
  end

  test "show says when a project has no sources" do
    get project_path(projects(:mersey_green))
    assert_select "p", "No data sources in this project."
  end

  test "edit shows the form" do
    get edit_project_path(projects(:cwm))
    assert_response :success
    assert_select "h1", "Edit Cooperative World Map (CWM)"
    assert_select "select[name=?]", "project[category]"
    assert_select "input[name=?][value=?]", "project[position]", "10"
  end

  test "update changes name, description, category and position" do
    patch project_path(projects(:cwm)), params: {
      project: { name: "CWM", description: "Updated.", category: "legacy", position: "15" }
    }
    assert_redirected_to project_path(projects(:cwm))
    follow_redirect!
    assert_select "div", "Project updated."

    cwm = projects(:cwm).reload
    assert_equal "CWM", cwm.name
    assert_equal "Updated.", cwm.description
    assert cwm.legacy?
    assert_equal 15, cwm.position
  end

  test "update rejects a blank name" do
    patch project_path(projects(:cwm)), params: { project: { name: "" } }
    assert_response :unprocessable_entity
    assert_equal "Cooperative World Map (CWM)", projects(:cwm).reload.name
  end

  test "show offers a build for projects with unify settings" do
    get project_path(projects(:cwm))
    assert_select "h2", "Unified CSV builds"
    assert_select "form[action=?]", build_project_path(projects(:cwm))
    assert_select "td", "No builds yet."
  end

  test "show has no builds panel for other projects" do
    get project_path(projects(:mersey_green))
    assert_select "h2", text: "Unified CSV builds", count: 0
  end

  test "build queues a unified CSV build" do
    assert_enqueued_with(job: ProjectBuildJob) do
      post build_project_path(projects(:cwm))
    end
    assert_redirected_to project_path(projects(:cwm))
    assert projects(:cwm).project_builds.last.queued?
    follow_redirect!
    assert_select "div", "Build queued."
  end

  test "build refuses while a build is in progress" do
    projects(:cwm).project_builds.create!(status: :running)
    assert_no_enqueued_jobs do
      post build_project_path(projects(:cwm))
    end
    follow_redirect!
    assert_select "div", "A build is already in progress."
  end

  test "build is not found for projects without unify settings" do
    post build_project_path(projects(:mersey_green))
    assert_response :not_found
  end

  test "show lists builds and downloads the latest unified CSV" do
    dir = Dir.mktmpdir
    File.write(File.join(dir, "unified.csv"), "Identifier\n1\n")
    build = projects(:cwm).project_builds.create!(status: :succeeded, started_at: 1.minute.ago,
      finished_at: Time.current, archive_path: dir, row_count: 1, merged_count: 0)

    get project_path(projects(:cwm))
    assert_select "a[href=?]", project_build_path(build)
    assert_select "a[href=?]", csv_project_build_path(build), "Download unified CSV"

    get csv_project_build_path(build)
    assert_response :success
    assert_equal "Identifier\n1\n", response.body
    assert_match(/cwm-unified-#{build.id}\.csv/, response.headers["Content-Disposition"])

    get project_build_path(build)
    assert_response :success
    assert_select "h2", "Log"
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  test "build page offers the diff from the previous build" do
    dir = Dir.mktmpdir
    File.write(File.join(dir, "diff.txt"), "+ added\n")
    build = projects(:cwm).project_builds.create!(status: :succeeded, archive_path: dir,
      rows_added: 1, rows_removed: 0, rows_changed: 0, diff_summary: "1 added, 0 removed, 0 changed (1 rows, was 0).")

    get project_build_path(build)
    assert_select "a[href=?]", diff_project_build_path(build), "Download diff"
    assert_select "p", /1 added, 0 removed, 0 changed/

    get diff_project_build_path(build)
    assert_equal "+ added\n", response.body
  ensure
    FileUtils.remove_entry(dir) if dir
  end
end
