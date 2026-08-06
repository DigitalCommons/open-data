require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { username: "settled", password: "password123" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { username: "settled", password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "signing in with the default password forces a password change" do
    post session_path, params: { username: "mykomaps", password: "admin" }
    assert_redirected_to root_path

    get root_path
    assert_redirected_to edit_password_path
  end

  test "destroy" do
    sign_in_as(users(:settled))

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end
