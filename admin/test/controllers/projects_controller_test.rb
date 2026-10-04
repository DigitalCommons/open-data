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
end
