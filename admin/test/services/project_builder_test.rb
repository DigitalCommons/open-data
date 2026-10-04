require "test_helper"
require "csv"

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

  test "cleans each source into the archive with the clean log" do
    @settings = UnifySettings.from_definition(
      "match_on" => [ "Domains" ],
      "tables" => {
        "al" => { "source" => "alpha", "row_filter" => { "Status" => "1" } },
        "be" => { "source" => "beta" }
      }
    )
    archive_standard_csv(data_sources(:alpha), "Identifier,Name,Website,Status\n1,One,https://one.coop,1\n2,Two,,0\n")
    archive_standard_csv(data_sources(:beta), "Identifier,Name,Website\n9,Nine,https://x.coop/path\n")

    build = build!
    assert build.succeeded?, build.log
    cleaned = Pathname.new(build.archive_path) + "cleaned"
    assert_equal "Identifier,Name,Website,Status,Domains,Dataset\n1,One,https://one.coop,1,one.coop,al\n",
      File.read(cleaned + "al.cleaned.csv")
    assert File.file?(cleaned + "be.cleaned.csv")

    tsv = File.read(cleaned + "clean-csv-data.tsv").lines
    assert_equal "datasetId\tid\ttype\tmessage\turl\tdomain\n", tsv.first
    assert_includes tsv, "be\t9\terror\turl must not have path\thttps://x.coop/path\tx.coop\n"
    assert_match(/al: 1 rows/, build.log)
  end

  test "unifies the cleaned sources into unified.csv" do
    archive_standard_csv(data_sources(:alpha), "Identifier,Name,Website\n1,One,https://one.coop\n2,Two,https://two.coop\n")
    archive_standard_csv(data_sources(:beta), "Identifier,Name,Website\n9,Uno,https://www.one.coop\n")

    build = build!
    assert build.succeeded?, build.log
    rows = CSV.read(build.csv_path, headers: true)
    assert_equal [ "al/1", "al/2" ], rows.map { |row| row["Identifier"] }
    assert_equal "AL;BE", rows.first["Memberships"]
    assert_equal 2, build.row_count
    assert_equal 1, build.merged_count
    assert_match(/2 rows, 1 merged/, build.log)
  end

  test "compares each build with the project's previous successful build" do
    alpha = data_sources(:alpha)
    archive_standard_csv(alpha, "Identifier,Name\n1,One\n2,Two\n")
    archive_standard_csv(data_sources(:beta), "Identifier,Name\n9,Nine\n")
    first = build!
    assert_equal [ 3, 0, 0 ], [ first.rows_added, first.rows_removed, first.rows_changed ]

    archive_standard_csv(alpha, "Identifier,Name\n1,One renamed\n3,Three\n")
    @build = projects(:cwm).project_builds.create!(status: :queued)
    second = build!

    assert second.succeeded?, second.log
    assert_equal [ 1, 1, 1 ], [ second.rows_added, second.rows_removed, second.rows_changed ]
    assert_match(/1 added, 1 removed, 1 changed/, second.diff_summary)
    assert File.file?(second.diff_path)
  end
end
