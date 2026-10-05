require "test_helper"
require "csv"

class RowStampsBackfillTest < ActiveSupport::TestCase
  include OpenDataTestHelper

  setup do
    setup_open_data_env
    @source = data_sources(:alpha)
    @source.download_runs.destroy_all
  end

  teardown { teardown_open_data_env }

  def archived(csv, at)
    archive_standard_csv(@source, csv).tap { |run| run.update!(started_at: at, created_at: at) }
  end

  def stamps(run)
    CSV.read(run.standard_csv_path, headers: true).to_h { |row| [ row["Identifier"], row.values_at("Created At", "Updated At") ] }
  end

  test "replays archived downloads in order and stamps the latest one" do
    t1 = Time.utc(2026, 10, 1, 8)
    t2 = Time.utc(2026, 10, 2, 8)
    t3 = Time.utc(2026, 10, 3, 8)
    archived("Identifier,Name\n1,One\n2,Two\n", t1)
    archived("Identifier,Name\n1,One\n2,Two renamed\n", t2)
    latest = archived("Identifier,Name\n1,One\n2,Two renamed\n3,Three\n", t3)

    assert_equal :stamped, RowStamps::Backfill.new(@source).call
    assert_equal({ "1" => [ t1.iso8601, t1.iso8601 ], "2" => [ t1.iso8601, t2.iso8601 ], "3" => [ t3.iso8601, t3.iso8601 ] }, stamps(latest))
  end

  test "dates an imported download by the original file's modified time" do
    run = archived("Identifier,Name\n1,One\n", Time.utc(2026, 10, 4, 20))
    File.write(File.join(run.archive_path, "meta.json"), { standard_csv_modified_at: "2025-06-22T16:35:24Z" }.to_json)

    RowStamps::Backfill.new(@source).call
    assert_equal [ "2025-06-22T16:35:24Z" ] * 2, stamps(run)["1"]
  end

  test "leaves a source alone when its latest download is already stamped" do
    archived("Identifier,Name,Created At,Updated At\n1,One,2026-01-01T00:00:00Z,2026-01-01T00:00:00Z\n", Time.utc(2026, 10, 1))
    assert_equal :already_stamped, RowStamps::Backfill.new(@source).call
  end

  test "does nothing for a source with no downloads" do
    assert_equal :no_downloads, RowStamps::Backfill.new(@source).call
  end
end
