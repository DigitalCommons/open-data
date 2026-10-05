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
end
