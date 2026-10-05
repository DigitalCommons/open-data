class ProjectDatasetJob < ApplicationJob
  queue_as :default

  limits_concurrency key: ->(dataset) { "dataset-#{dataset.project_id}" }, duration: 4.hours

  def perform(dataset)
    ProjectDatasetBuilder.new(dataset).call
    DiskUsageJob.perform_later
  end
end
