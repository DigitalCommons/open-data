require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get edit_password_path
    assert_redirected_to new_session_path
  end

  test "edit renders the settings page for a signed-in user" do
    sign_in_as(users(:settled))
    get edit_password_path
    assert_response :success
    assert_select "h1", "Settings"
    assert_select "h2", "Change password"
    assert_select "p", "Change your password"
    assert_select "input[type=password][name=current_password]"
  end

  test "a user on the default password is redirected everywhere except the password page" do
    sign_in_as(users(:mykomaps))

    get root_path
    assert_redirected_to edit_password_path

    get edit_password_path
    assert_response :success
  end

  test "update with correct current password clears the forced change" do
    user = users(:mykomaps)
    sign_in_as(user)

    patch password_path, params: {
      current_password: "admin", password: "new password 1", password_confirmation: "new password 1"
    }
    assert_redirected_to root_path
    assert_not user.reload.must_change_password?
    assert user.authenticate("new password 1")

    get root_path
    assert_response :success
  end

  test "update rejects a wrong current password" do
    sign_in_as(users(:mykomaps))
    patch password_path, params: {
      current_password: "wrong", password: "new password 1", password_confirmation: "new password 1"
    }
    assert_response :unprocessable_entity
    assert users(:mykomaps).reload.must_change_password?
  end

  test "update rejects reusing the current password" do
    sign_in_as(users(:mykomaps))
    patch password_path, params: {
      current_password: "admin", password: "admin", password_confirmation: "admin"
    }
    assert_response :unprocessable_entity
    assert users(:mykomaps).reload.must_change_password?
  end

  test "update rejects mismatched confirmation" do
    sign_in_as(users(:mykomaps))
    patch password_path, params: {
      current_password: "admin", password: "new password 1", password_confirmation: "different"
    }
    assert_response :unprocessable_entity
  end

  test "update rejects a too-short password" do
    sign_in_as(users(:mykomaps))
    patch password_path, params: {
      current_password: "admin", password: "short", password_confirmation: "short"
    }
    assert_response :unprocessable_entity
  end
end
