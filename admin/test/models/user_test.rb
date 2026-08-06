require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "must_change_password? is true until password_changed_at is set" do
    assert users(:mykomaps).must_change_password?
    assert_not users(:settled).must_change_password?
  end

  test "username is normalized" do
    user = User.create!(username: "  MyUser  ", password: "password123")
    assert_equal "myuser", user.username
  end

  test "username must be unique" do
    dupe = User.new(username: "mykomaps", password: "password123")
    assert_not dupe.valid?
    assert_includes dupe.errors[:username], "has already been taken"
  end

  test "authenticate_by with username and password" do
    assert_equal users(:mykomaps), User.authenticate_by(username: "mykomaps", password: "admin")
    assert_nil User.authenticate_by(username: "mykomaps", password: "wrong")
  end

  test "password length enforced on password_change context" do
    user = users(:settled)
    user.password = "short"
    assert_not user.save(context: :password_change)
    user.password = "long enough"
    assert user.save(context: :password_change)
  end
end
