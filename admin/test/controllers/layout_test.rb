require "test_helper"

class LayoutTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:settled)) }

  test "header names the app and marks the current page" do
    get root_path
    assert_select "title", /MykoMaps OpenData/
    assert_select ".wordmark", "MykoMaps OpenData"
    assert_select "nav a[aria-current=page]", "Projects & Data Sources"
    assert_select "nav a[href=?]", edit_password_path, "Settings"

    get edit_password_path
    assert_select "nav a[aria-current=page]", "Settings"
  end

  test "detail pages count as Projects & Data Sources in the menu" do
    get project_path(projects(:cwm))
    assert_select "nav a[aria-current=page]", "Projects & Data Sources"
  end

  test "header shows the deployed version from CloudronManifest.json after the name" do
    version = JSON.parse(File.read(Rails.root.join("../CloudronManifest.json"))).fetch("version")
    assert_equal version, ApplicationHelper::APP_VERSION
    get root_path
    assert_select ".bar-left .app-version", "v#{version}"
  end

  test "the sign-in page does not show the version" do
    sign_out
    get new_session_path
    assert_select ".app-version", count: 0
  end
end
