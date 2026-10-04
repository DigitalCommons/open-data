require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "requires a unique key and a name" do
    project = Project.new(key: "cwm", name: "", category: :legacy)
    assert_not project.valid?
    assert project.errors.of_kind?(:key, :taken)
    assert project.errors.of_kind?(:name, :blank)
  end

  test "position must be a whole number of zero or more" do
    project = projects(:cwm)
    project.position = -1
    assert_not project.valid?
    project.position = 1.5
    assert_not project.valid?
    project.position = 0
    assert project.valid?
  end

  test "ordered lists by position, whatever the category" do
    Project.create!(key: "old", name: "Old", category: :legacy, position: 5)
    Project.create!(key: "powys", name: "Powys Food Map", category: :mykomaps_v4, position: 20)

    assert_equal %w[ old cwm powys mersey-green ], Project.ordered.map(&:key)
  end

  test "category_label names the MykoMaps generation" do
    assert_equal "MykoMaps v4", projects(:cwm).category_label
    assert_equal "MykoMaps v3", projects(:mersey_green).category_label
    assert_equal "Legacy", Project.new(category: :legacy).category_label
  end

  test "removing a project leaves its sources unassigned" do
    projects(:cwm).destroy!
    assert_nil data_sources(:alpha).reload.project
  end

  test "sync_from_file! creates projects in file order and assigns their sources" do
    Project.sync_from_file!(definitions: {
      "powys" => { "name" => "Powys Food Map", "category" => "mykomaps_v4",
                   "description" => "Food system.", "sources" => [ "beta" ] },
      "old" => { "name" => "Old", "category" => "legacy", "description" => "Old map.", "sources" => [] }
    })

    powys = Project.find_by!(key: "powys")
    assert_equal "Powys Food Map", powys.name
    assert powys.mykomaps_v4?
    assert_equal "Food system.", powys.description
    assert_equal [ data_sources(:beta) ], powys.data_sources.to_a
    assert_equal 10, powys.position
    assert_equal 20, Project.find_by!(key: "old").position
  end

  test "sync_from_file! keeps UI edits and existing source assignments" do
    cwm = projects(:cwm)
    cwm.update!(name: "Edited", description: "", category: :legacy, position: 55)

    Project.sync_from_file!(definitions: {
      "cwm" => { "name" => "Cooperative World Map (CWM)", "category" => "mykomaps_v4",
                 "description" => "From file.", "sources" => [] },
      "other" => { "name" => "Other", "category" => "legacy", "description" => "Other.",
                   "sources" => [ "alpha", "missing" ] }
    })

    cwm.reload
    assert_equal "Edited", cwm.name
    assert cwm.legacy?
    assert_equal 55, cwm.position, "edited position must survive"
    assert_equal "From file.", cwm.description, "blank description should be filled"
    assert_equal cwm, data_sources(:alpha).reload.project, "assigned source must not move"
    assert_nil DataSource.find_by(directory: "missing")
  end

  test "projects file parses with a name, category, description and unique sources" do
    definitions = Project.project_definitions
    assert definitions.any?
    sources = []
    definitions.each do |key, info|
      assert_match(/\A[\w-]+\z/, key)
      assert info["name"].present?, "#{key} needs a name"
      assert info["description"].present?, "#{key} needs a description"
      assert_includes Project.categories.keys, info["category"], "#{key} has an unknown category"
      sources.concat(Array(info["sources"]))
    end
    assert_equal sources.uniq, sources, "a source may belong to only one project"
  end

  test "projects file names only source directories in the repo" do
    listed = Project.project_definitions.values.flat_map { |info| Array(info["sources"]) }
    assert_empty listed - OpenData.source_directories
  end

  test "projects file lists v4 first, then v3, then legacy" do
    categories = Project.project_definitions.values.map { |info| info["category"] }
    assert_equal categories.sort_by { |t| Project.categories[t] }, categories
  end
end
