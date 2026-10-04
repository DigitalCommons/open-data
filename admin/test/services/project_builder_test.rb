require "test_helper"

class ProjectBuilderTest < ActiveSupport::TestCase
  include OpenDataTestHelper

  setup do
    setup_open_data_env
    @settings = UnifySettings.from_definition(
      "match_on" => [ "Domains" ],
      "tables" => {
        "al" => { "source" => "alpha", "match" => { "Domains" => "Domains" } },
        "be" => { "source" => "beta", "match" => { "Domains" => "Domains" } }
      }
    )
    @build = projects(:cwm).project_builds.create!(status: :queued)
  end

  teardown { teardown_open_data_env }

  def build!
    ProjectBuilder.new(@build, settings: @settings).call
  end

  test "fails, naming the source, when a source has no converted output" do
    DownloadRun.delete_all
    archive_standard_csv(data_sources(:alpha), default_csv)

    build = build!
    assert build.failed?
    assert_match(/beta has no converted standard\.csv/, build.log)
    assert_nil build.csv_path
  end

  test "archives the unified CSV with the inputs it used" do
    alpha_run = archive_standard_csv(data_sources(:alpha), default_csv)
    archive_standard_csv(data_sources(:beta), default_csv)

    build = build!
    assert build.succeeded?, build.log
    assert File.file?(build.csv_path)
    assert build.started_at && build.finished_at

    meta = JSON.parse(File.read(File.join(build.archive_path, "meta.json")))
    assert_equal "cwm", meta["project"]
    assert_equal [ "al", "be" ], meta["inputs"].map { |input| input["code"] }
    assert_equal alpha_run.id, meta["inputs"].first["download_run_id"]
  end

  test "records unexpected errors in the log" do
    archive_standard_csv(data_sources(:alpha), default_csv)
    archive_standard_csv(data_sources(:beta), "not,a\n\"broken")

    build = build!
    assert build.failed?
    assert_match(/CSV::MalformedCSVError|Unclosed quoted field/, build.log)
  end
end
