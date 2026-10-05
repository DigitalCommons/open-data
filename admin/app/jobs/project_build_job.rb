class ProjectBuildJob < ApplicationJob
  queue_as :default

  # One build per project at a time (Solid Queue only; see DataSourceRunJob).
  limits_concurrency key: ->(build) { build.project_id }, duration: 4.hours

  def perform(build)
    ProjectBuilder.new(build).call
    DiskUsageJob.perform_later
  end
end
