module DataBuilder
  # Sweeps expired staged uploads. Built zips are kept, like the app's other
  # downloads and builds.
  class CleanupJob < ApplicationJob
    queue_as :default

    def perform
      DataBuilder.sweep_uploads!
    end
  end
end
