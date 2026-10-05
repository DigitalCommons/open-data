require "test_helper"

# End-to-end engine test: stage a CSV, build, poll, download the zip.
class DataBuilderFlowTest < ActionDispatch::IntegrationTest
  include OpenDataTestHelper

  setup do
    @data_builder_tmp = Dir.mktmpdir("data-builder-test")
    @saved_root = ENV["DATA_BUILDER_ROOT"]
    ENV["DATA_BUILDER_ROOT"] = @data_builder_tmp
    sign_in_as(users(:settled))
  end

  teardown do
    @saved_root ? ENV["DATA_BUILDER_ROOT"] = @saved_root : ENV.delete("DATA_BUILDER_ROOT")
    FileUtils.remove_entry(@data_builder_tmp)
  end

  def fixture_config
    JSON.parse(File.read(file_fixture("dataset-cli/config.json")))
  end

  test "the wizard needs a signed-in user" do
    get "/data-builder/"
    assert_response :success
    assert_match(/dataset builder/, response.body)

    sign_out
    get "/data-builder/"
    assert_redirected_to "/session/new"
    post "/data-builder/csvs", params: { file: fixture_file_upload("dataset-cli/dummy.csv", "text/csv") }
    assert_redirected_to "/session/new"
  end

  test "stage, build and download a dataset zip" do
    post "/data-builder/csvs", params: { file: fixture_file_upload("dataset-cli/dummy.csv", "text/csv") }
    assert_response :created
    staged = response.parsed_body
    assert_match(/\A[a-f0-9]{16}\z/, staged["id"])
    assert_equal "dummy.csv", staged["filename"]
    assert_equal 4, staged["inspection"]["rowCount"]

    perform_enqueued_jobs do
      post "/data-builder/builds", params: {
        name: "dummy", displayName: "Dummy Map", csvId: staged["id"], config: fixture_config
      }, as: :json
      assert_response :created
    end
    build_id = response.parsed_body["id"]

    get "/data-builder/builds/#{build_id}"
    assert_response :success
    body = response.parsed_body
    assert_equal "succeeded", body["status"], "error: #{body['error']}"
    assert_match(/4 items/, body["message"])

    get body["downloadUrl"]
    assert_response :success
    assert_equal "application/zip", response.media_type

    entries = {}
    Zip::File.open_buffer(response.body) do |zip|
      zip.each { |e| entries[e.name] = e.get_input_stream.read unless e.directory? }
    end
    assert_includes entries.keys, "config.json"
    assert_includes entries.keys, "locations.json"
    assert_includes entries.keys, "searchable.json"
    assert_includes entries.keys, "items/0.json"
    assert_includes entries.keys, "items/3.json"
    assert_includes entries.keys, "meta.json"
    assert_includes entries.keys, "source.csv"

    config = JSON.parse(entries["config.json"])
    assert_equal "70%", config["popup"]["leftPaneWidth"]
    meta = JSON.parse(entries["meta.json"])
    assert_equal "Dummy Map", meta["displayName"]
    assert_equal "csv-build", meta.dig("source", "type")
    assert_equal "dummy.csv", meta.dig("source", "filename")
    locations = JSON.parse(entries["locations.json"])
    assert_equal 4, locations.length
  end

  test "build rejects an invalid config with zod-style issues" do
    post "/data-builder/csvs", params: { file: fixture_file_upload("dataset-cli/dummy.csv", "text/csv") }
    staged = response.parsed_body

    bad = fixture_config
    bad["languages"] = []
    post "/data-builder/builds", params: { name: "dummy", csvId: staged["id"], config: bad }, as: :json
    assert_response :bad_request
    assert_match(/languages/, response.parsed_body["message"])
  end

  test "build rejects an unknown csv or bad name" do
    post "/data-builder/builds", params: { name: "x y", csvId: "0" * 16, config: fixture_config }, as: :json
    assert_response :bad_request

    post "/data-builder/builds", params: { name: "ok-name", csvId: "0" * 16, config: fixture_config }, as: :json
    assert_response :bad_request
    assert_match(/unknown CSV upload/, response.parsed_body["message"])
  end

  test "a failed build reports its error" do
    post "/data-builder/csvs", params: { file: fixture_file_upload("dataset-cli/dummy.csv", "text/csv") }
    staged = response.parsed_body

    # Sabotage: value map rewrites a valid vocab value into garbage
    perform_enqueued_jobs do
      post "/data-builder/builds", params: {
        name: "broken", csvId: staged["id"], config: fixture_config,
        valueMaps: { "Activity" => { "AM130" => "NOT_A_TERM" } }
      }, as: :json
    end
    get "/data-builder/builds/#{response.parsed_body['id']}"
    body = response.parsed_body
    assert_equal "failed", body["status"]
    assert_match(/failed to build dataset/, body["error"])
  end

  test "staging from an admin data source" do
    setup_open_data_env
    begin
      source = data_sources(:alpha)
      run = source.download_runs.create!(status: :succeeded, triggered_by: :manual,
        started_at: Time.current, finished_at: Time.current)
      dir = OpenData.downloads_root + "alpha/2026-01-01_000000"
      FileUtils.mkdir_p(dir)
      File.write(dir + "standard.csv", "Identifier,Name\n1,One\n")
      run.update!(archive_path: dir.to_s)

      get "/data-builder/sources"
      assert_response :success
      assert(response.parsed_body["sources"].any? { |s| s["directory"] == "alpha" })

      post "/data-builder/csvs/from_source/#{source.id}"
      assert_response :created
      body = response.parsed_body
      assert_equal "alpha-standard.csv", body["filename"]
      assert_equal 1, body["inspection"]["rowCount"]
      assert_equal %w[Identifier Name], body["inspection"]["headers"]
    ensure
      teardown_open_data_env
    end
  end

  test "templates CRUD" do
    put "/data-builder/templates/my-template", params: {
      description: "A test", state: { name: "x", languages: [ "en" ] }
    }, as: :json
    assert_response :success

    get "/data-builder/templates"
    templates = response.parsed_body["templates"]
    assert_equal [ "my-template" ], templates.map { |t| t["name"] }
    assert_equal "A test", templates.first["description"]

    get "/data-builder/templates/my-template"
    assert_response :success
    assert_equal "x", response.parsed_body.dig("state", "name")

    delete "/data-builder/templates/my-template"
    assert_response :success

    get "/data-builder/templates/my-template"
    assert_response :not_found
  end

  test "template validation" do
    put "/data-builder/templates/bad%20name%21", params: { state: {} }, as: :json
    assert_response :bad_request

    put "/data-builder/templates/no-state", params: {}, as: :json
    assert_response :bad_request
  end
end
