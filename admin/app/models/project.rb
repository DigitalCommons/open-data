# A map or dataset built from one or more data sources.
class Project < ApplicationRecord
  has_many :data_sources, dependent: :nullify

  # Which MykoMaps generation serves the project.
  enum :category, { mykomaps_v4: 0, mykomaps_v3: 1, legacy: 2 }

  CATEGORY_LABELS = { "mykomaps_v4" => "MykoMaps v4", "mykomaps_v3" => "MykoMaps v3", "legacy" => "Legacy" }.freeze

  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Dashboard order: lowest position first.
  scope :ordered, -> { order(:position, :name) }

  # Gap between seeded positions, leaving room to slot projects in between.
  POSITION_STEP = 10

  # Projects and their sources, applied by sync_from_file!.
  DEFINITIONS_FILE = "db/projects.yml".freeze

  def self.project_definitions
    path = Rails.root.join(DEFINITIONS_FILE)
    path.file? ? YAML.load_file(path) : {}
  end

  # Create missing projects and assign listed sources that have no project.
  # New projects are positioned 10, 20, 30... in file order. Like
  # DataSource.sync_from_repo!, existing records only gain a description
  # when blank, so edits made in the UI survive re-seeding.
  def self.sync_from_file!(definitions: project_definitions)
    definitions.each_with_index do |(key, info), index|
      project = find_or_initialize_by(key: key)
      if project.new_record?
        project.assign_attributes(name: info["name"], category: info["category"],
          position: (index + 1) * POSITION_STEP)
      end
      project.description = info["description"] if project.description.blank?
      project.save! if project.new_record? || project.changed?

      DataSource.where(directory: Array(info["sources"]), project_id: nil).update_all(project_id: project.id)
    end
  end

  def category_label
    CATEGORY_LABELS.fetch(category)
  end
end
