require "test_helper"

class SecretsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:settled)) }

  test "settings lists each secret without revealing its value" do
    Secret.create!(key: "geoapify", value: "very-secret-geo-1a2b")
    get edit_password_path
    assert_select "h2", "Secrets"
    assert_select "label", "Geoapify API key"
    assert_select "input[type=password][name=?][placeholder=?]", "secrets[geoapify][value]", "…1a2b"
    assert_select "input[type=password][name=?]:not([placeholder])", "secrets[mapbox][value]"
    assert_select "a[href=?]", "https://myprojects.geoapify.com"
    assert_select "p", /Set, saved/
    assert_select "p", /Not set/
    assert_not_includes response.body, "very-secret-geo"
  end

  test "update saves filled values, keeps blank ones and removes ticked ones" do
    Secret.create!(key: "mapbox", value: "keep-me")
    Secret.create!(key: "airtable", value: "remove-me")
    patch secrets_path, params: { secrets: {
      geoapify: { value: "new-geo" }, mapbox: { value: "" }, airtable: { value: "", remove: "1" }
    } }
    assert_redirected_to edit_password_path
    follow_redirect!
    assert_select "div", "Secrets saved."

    assert_equal "new-geo", Secret.find_by!(key: "geoapify").value
    assert_not Secret.find_by!(key: "geoapify").from_env?
    assert_equal "keep-me", Secret.find_by!(key: "mapbox").value
    assert_nil Secret.find_by(key: "airtable")
  end

  test "requires authentication" do
    sign_out
    patch secrets_path, params: { secrets: { geoapify: { value: "x" } } }
    assert_redirected_to new_session_path
    assert_nil Secret.find_by(key: "geoapify")
  end
end
