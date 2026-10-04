# A data source's membership of a project.
class ProjectSource < ApplicationRecord
  belongs_to :project
  belongs_to :data_source

  validates :data_source_id, uniqueness: { scope: :project_id }
end
