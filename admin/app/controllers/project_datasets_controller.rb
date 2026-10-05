class ProjectDatasetsController < ApplicationController
  def download
    dataset = ProjectDataset.find(params[:id])
    path = dataset.zip_path
    return redirect_to dataset.project, alert: "No converted output available yet." unless path
    send_file path, filename: dataset.download_filename, type: "application/zip"
  end
end
