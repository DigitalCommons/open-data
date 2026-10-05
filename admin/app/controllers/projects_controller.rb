class ProjectsController < ApplicationController
  before_action :set_project

  def show
    @data_sources = @project.data_sources.order(enabled: :desc, name: :asc)
    @builds = @project.project_builds.order(created_at: :desc).limit(50)
    @map_config = MapConfig.for(@project.key)
    @datasets = @project.project_datasets.order(created_at: :desc).limit(20)
    @unify_codes = @project.unify_settings&.tables.to_a.to_h { |table| [ table.source, table.code ] }
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Project updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Queue a unified CSV build.
  def build
    return head :not_found unless @project.buildable?
    return redirect_to @project, alert: "A build is already in progress." if @project.building?

    build = @project.project_builds.create!(status: :queued)
    ProjectBuildJob.perform_later(build)
    redirect_to @project, notice: "Build queued."
  end

  # Queue a MykoMaps dataset build from the latest unified CSV.
  def build_dataset
    return head :not_found unless MapConfig.for(@project.key)
    unified = @project.project_builds.succeeded.order(created_at: :desc).find(&:csv_path)
    return redirect_to @project, alert: "Build the unified CSV first." unless unified

    dataset = @project.project_datasets.create!(project_build: unified, status: :queued)
    ProjectDatasetJob.perform_later(dataset)
    redirect_to @project, notice: "Dataset build queued."
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.expect(project: [ :name, :description, :category, :position ])
  end
end
