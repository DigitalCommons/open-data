module DataBuilder
  # One dataset build: a staged CSV plus the wizard's build request,
  # processed by BuildJob into a downloadable zip.
  class Build < ApplicationRecord
    enum :status, { queued: 0, running: 1, succeeded: 2, failed: 3 }

    validates :name, presence: true, format: { with: ApplicationController::ADMIN_ID }
    validates :csv_id, presence: true

    def request_data
      @request_data ||= JSON.parse(request || "{}")
    end

    def zip_path
      DataBuilder.builds_dir + "#{id}.zip"
    end

    def append_log(text)
      self.log = [ log, text ].compact.join
    end
  end
end
