require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  include OpenDataTestHelper

  setup { setup_open_data_env }
  teardown { teardown_open_data_env }

  test "the default user is only created when there are no users" do
    users(:mykomaps).update!(username: "renamed")
    assert_no_difference -> { User.count } do
      load Rails.root.join("db/seeds.rb")
    end
    assert_nil User.find_by(username: "mykomaps")
  end
end
