class ProjectsController < ApplicationController
  before_action :set_project

  def show
    @data_sources = @project.data_sources.order(enabled: :desc, name: :asc)
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

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.expect(project: [ :name, :description, :category, :position ])
  end
end
