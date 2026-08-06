require "test_helper"

class DataSourceRunJobTest < ActiveJob::TestCase
  include OpenDataTestHelper

  setup { setup_open_data_env }
  teardown { teardown_open_data_env }

  test "performs the run end to end" do
    create_project("alpha")
    source = data_sources(:alpha)
    source.download_runs.destroy_all
    run = source.download_runs.create!(status: :queued, triggered_by: :manual)

    DataSourceRunJob.perform_now(run)

    assert run.reload.succeeded?, "log: #{run.log}"
    assert source.reload.last_downloaded_at.present?
  end
end
