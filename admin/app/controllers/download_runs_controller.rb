class DownloadRunsController < ApplicationController
  before_action :set_run

  def show
  end

  def standard_csv
    path = @run.standard_csv_path
    return redirect_to @run, alert: "No standard.csv archived for this run." unless path
    send_file path, filename: @run.download_filename("standard.csv"), type: "text/csv"
  end

  def diff
    path = @run.diff_path
    return redirect_to @run, alert: "No diff recorded for this run." unless path
    send_file path, filename: @run.download_filename("diff.txt"), type: "text/plain"
  end

  private

  def set_run
    @run = DownloadRun.find(params[:id])
  end
end
