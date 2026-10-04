class ProjectsController < ApplicationController
  before_action :set_project

  def show
    @data_sources = @project.data_sources.order(enabled: :desc, name: :asc)
    @builds = @project.project_builds.order(created_at: :desc).limit(50)
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

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.expect(project: [ :name, :description, :category, :position ])
  end
end
