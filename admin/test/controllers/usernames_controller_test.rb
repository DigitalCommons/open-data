require "test_helper"

class UsernamesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:settled)
    sign_in_as(@user)
  end

  test "settings shows Change username first, then Change password, then Secrets" do
    get edit_password_path
    assert_select "input[name=username][value=?]", "settled"
    body = response.body
    assert_operator body.index(">Change username<"), :<, body.index(">Change password<")
    assert_operator body.index(">Change password<"), :<, body.index(">Secrets<")
  end

  test "update changes the username with the current password and keeps the session" do
    patch username_path, params: { username: " NewName ", current_password: "password123" }
    assert_redirected_to edit_password_path
    follow_redirect!
    assert_select "div", "Username updated."
    assert_equal "newname", @user.reload.username
    assert_select "form[action=?] button", session_path, "Sign out newname"
  end

  test "update refuses a wrong current password" do
    patch username_path, params: { username: "other", current_password: "wrong" }
    assert_response :unprocessable_entity
    assert_select "div", "Current password is incorrect."
    assert_equal "settled", @user.reload.username
  end

  test "update refuses a blank or taken username" do
    patch username_path, params: { username: "", current_password: "password123" }
    assert_response :unprocessable_entity
    assert_select "div", /Username can't be blank/

    patch username_path, params: { username: "mykomaps", current_password: "password123" }
    assert_response :unprocessable_entity
    assert_select "div", /Username has already been taken/
    assert_equal "settled", @user.reload.username
  end

  test "requires authentication" do
    sign_out
    patch username_path, params: { username: "x", current_password: "password123" }
    assert_redirected_to new_session_path
  end
end
