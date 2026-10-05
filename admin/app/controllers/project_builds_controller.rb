class ProjectBuildsController < ApplicationController
  before_action :set_build

  def show
  end

  def csv
    path = @build.csv_path
    return redirect_to @build, alert: "No converted output available yet." unless path
    send_file path, filename: @build.download_filename("unified.csv"), type: "text/csv"
  end

  def diff
    path = @build.diff_path
    return redirect_to @build, alert: "No diff recorded for this run." unless path
    send_file path, filename: @build.download_filename("diff.txt"), type: "text/plain"
  end

  private

  def set_build
    @build = ProjectBuild.find(params[:id])
  end
end
