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

  test "removing a project keeps its sources, without the project" do
    projects(:cwm).destroy!
    assert_empty data_sources(:alpha).reload.projects
  end

  test "a source can belong to several projects, but only once to each" do
    projects(:mersey_green).data_sources << data_sources(:alpha)
    assert_equal [ projects(:cwm), projects(:mersey_green) ], data_sources(:alpha).projects.ordered.to_a

    duplicate = ProjectSource.new(project: projects(:cwm), data_source: data_sources(:alpha))
    assert_not duplicate.valid?
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

  test "sync_from_file! uses a position given in the file for new projects" do
    Project.sync_from_file!(definitions: {
      "dotcoop" => { "name" => "DotCoop", "category" => "mykomaps_v4", "position" => 24,
                     "description" => "DotCoop.", "sources" => [ "alpha" ] }
    })
    assert_equal 24, Project.find_by!(key: "dotcoop").position
  end

  test "sync_from_file! keeps UI edits and adds sources to every project listing them" do
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
    assert_equal [ "cwm", "other" ], data_sources(:alpha).reload.projects.map(&:key).sort,
      "source stays in its project and joins the other"
    assert_nil DataSource.find_by(directory: "missing")
  end

  test "projects file parses with a name, category, description and sources" do
    definitions = Project.project_definitions
    assert definitions.any?
    definitions.each do |key, info|
      assert_match(/\A[\w-]+\z/, key)
      assert info["name"].present?, "#{key} needs a name"
      assert info["description"].present?, "#{key} needs a description"
      assert_includes Project.categories.keys, info["category"], "#{key} has an unknown category"
      sources = Array(info["sources"])
      assert_equal sources.uniq, sources, "#{key} lists a source twice"
    end
  end

  test "projects file names only source directories in the repo" do
    listed = Project.project_definitions.values.flat_map { |info| Array(info["sources"]) }
    assert_empty listed - OpenData.source_directories
  end

  test "projects file lists v4 first, then v3, then legacy" do
    categories = Project.project_definitions.values.map { |info| info["category"] }
    assert_equal categories.sort_by { |t| Project.categories[t] }, categories
  end

  test "projects file has standalone DotCoop and Workers.coop projects sharing CWM's sources" do
    definitions = Project.project_definitions
    assert_equal [ "dotcoop" ], definitions.dig("dotcoop", "sources")
    assert_equal [ "workers-coop" ], definitions.dig("workers-coop", "sources")
    assert_includes definitions.dig("cwm", "sources"), "dotcoop"
    assert_includes definitions.dig("cwm", "sources"), "workers-coop"
  end

  test "CWM description ends with the field priority note" do
    description = Project.project_definitions.dig("cwm", "description")
    assert description.end_with?("so merged records take each field from the first source alphabetically. To be fixed."), description
    assert_includes description, "Note: the unified CSV matches data-pipelines, including its bug"
  end
end
