require "test_helper"
require "open3"
require "tmpdir"

# Drives deploy.sh (repo root) non-interactively against the stub cloudron
# CLI in test/stub_bin and checks the commands it issues.
class DeployScriptTest < ActiveSupport::TestCase
  ROOT = Rails.root.join("..").expand_path
  SCRIPT = ROOT.join("deploy.sh")
  STUB_BIN = Rails.root.join("test/stub_bin").to_s
  VERSION = JSON.parse(File.read(ROOT.join("CloudronManifest.json")))["version"]

  setup do
    @tmp = Dir.mktmpdir("deploy-test")
    @log = File.join(@tmp, "cloudron.log")
    @config = File.join(@tmp, "deploy.conf")
  end

  teardown { FileUtils.remove_entry(@tmp) }

  test "builds the image tagged with the manifest version, then installs a new app" do
    status = run_script
    assert status.success?, @output
    assert_includes calls, "builder build --repository opendata --tag #{VERSION}"
    assert_includes calls, "--server my.example.com list"
    assert_includes calls, "--server my.example.com install --location data.example.com --last-build"
    assert_not calls.any? { |c| c.include?(" update ") }
  end

  test "updates an app that is already installed at the location" do
    status = run_script(apps: "data.example.com")
    assert status.success?, @output
    assert_includes calls, "--server my.example.com update --app data.example.com --last-build"
    assert_not calls.any? { |c| c.include?(" install ") }
  end

  test "skips the backup when asked" do
    run_script(apps: "data.example.com", env: { "DEPLOY_NO_BACKUP" => "1" })
    assert_includes calls, "--server my.example.com update --app data.example.com --last-build --no-backup"
  end

  test "saves the answers for the next run" do
    run_script
    saved = File.read(@config)
    assert_includes saved, "DEPLOY_SERVER=my.example.com"
    assert_includes saved, "DEPLOY_REGISTRY=registry.example.com"
    assert_includes saved, "DEPLOY_REPOSITORY=opendata"
    assert_includes saved, "DEPLOY_LOCATION=data.example.com"
  end

  test "without a terminal, a missing answer stops the script before anything runs" do
    status = run_script(env: { "DEPLOY_LOCATION" => nil })
    assert_not status.success?
    assert_includes @output, "DEPLOY_LOCATION"
    assert_not File.exist?(@log)
  end

  private

  def run_script(apps: "", env: {})
    full_env = {
      "PATH" => "#{STUB_BIN}:#{ENV['PATH']}",
      "CLOUDRON_STUB_LOG" => @log,
      "CLOUDRON_STUB_APPS" => apps,
      "DEPLOY_CONFIG" => @config,
      "DEPLOY_SERVER" => "my.example.com",
      "DEPLOY_REGISTRY" => "registry.example.com",
      "DEPLOY_REPOSITORY" => "opendata",
      "DEPLOY_LOCATION" => "data.example.com"
    }.merge(env)
    @output, status = Open3.capture2e(full_env, "bash", SCRIPT.to_s, stdin_data: "")
    status
  end

  def calls
    File.exist?(@log) ? File.readlines(@log, chomp: true) : []
  end
end
