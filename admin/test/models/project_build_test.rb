require "test_helper"

class ProjectBuildTest < ActiveSupport::TestCase
  test "reap_stale! fails builds with no recent activity" do
    stale = projects(:cwm).project_builds.create!(status: :running, updated_at: 7.hours.ago)
    fresh = projects(:cwm).project_builds.create!(status: :running)

    ProjectBuild.reap_stale!

    assert stale.reload.failed?
    assert_match(/no activity/, stale.log)
    assert fresh.reload.running?
  end

  test "project knows when a build is running" do
    project = projects(:cwm)
    assert_not project.building?
    project.project_builds.create!(status: :queued)
    assert project.building?
  end

  test "only projects with unify settings in the projects file are buildable" do
    assert projects(:cwm).buildable?
    assert_not projects(:mersey_green).buildable?
  end

  test "input_count reads the number of sources from the archived meta.json" do
    Dir.mktmpdir do |dir|
      build = projects(:cwm).project_builds.create!(status: :succeeded, archive_path: dir)
      assert_nil build.input_count
      File.write(File.join(dir, "meta.json"), { inputs: [ { code: "a" }, { code: "b" } ] }.to_json)
      assert_equal 2, build.input_count
    end
  end
end
