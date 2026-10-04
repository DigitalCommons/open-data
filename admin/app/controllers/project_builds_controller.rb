class ProjectBuildsController < ApplicationController
  before_action :set_build

  def show
  end

  def csv
    path = @build.csv_path
    return redirect_to @build, alert: "No converted output available yet." unless path
    send_file path, filename: "#{@build.project.key}-unified-#{@build.id}.csv", type: "text/csv"
  end

  private

  def set_build
    @build = ProjectBuild.find(params[:id])
  end
end
