class DataSourceRunJob < ApplicationJob
  queue_as :default

  def perform(download_run)
    DataSourceRunner.new(download_run).call
  end
end
