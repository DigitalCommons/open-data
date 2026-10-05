module DataBuilder
  # Dataset builds: validate the request synchronously (so the wizard gets
  # instant config errors), run the pipeline in a background job, then serve
  # the built zip.
  class BuildsController < ApplicationController
    # POST /builds
    def create
      body = request_body
      name = body["name"]
      return send_message(400, "missing dataset name") if name.blank?
      return send_message(400, "invalid name - use letters, digits, - and _") unless valid_id?(name)

      csv_id = body["csvId"]
      unless csv_id.to_s.match?(/\A[a-f0-9]{16}\z/) && File.exist?(DataBuilder.uploads_dir + "#{csv_id}.csv")
        return send_message(400, "unknown CSV upload - please upload the CSV again")
      end

      begin
        Mykomap::Config.parse(body["config"])
      rescue Mykomap::Config::Invalid => e
        return send_message(400, e.message)
      end

      filename = begin
        JSON.parse(File.read(DataBuilder.uploads_dir + "#{csv_id}.meta.json"))["filename"]
      rescue Errno::ENOENT, JSON::ParserError
        nil
      end

      build = Build.create!(
        name: name,
        display_name: body["displayName"].presence,
        status: :queued,
        csv_id: csv_id,
        csv_filename: filename,
        request: JSON.generate(body.slice("config", "about", "valueMaps", "geocode", "project", "subProject"))
      )
      BuildJob.perform_later(build)
      render json: { id: build.id }, status: :created
    end

    # GET /builds/:id
    def show
      build = Build.find_by(id: params[:id])
      return send_message(404, "no such build") unless build
      payload = { id: build.id, name: build.name, status: build.status,
                  message: build.message, error: build.error }
      payload[:downloadUrl] = download_build_path(build) if build.succeeded?
      render json: payload
    end

    # GET /builds/:id/download
    def download
      build = Build.find_by(id: params[:id])
      return send_message(404, "no such build") unless build
      unless build.succeeded? && File.exist?(build.zip_path)
        return send_message(404, "no built dataset available for this build")
      end
      send_file build.zip_path, filename: DownloadFilename.for(build.created_at, build.name, "dataset.zip"), type: "application/zip"
    end

    private

    def request_body
      body = params.to_unsafe_h.except("controller", "action", "format", "build")
      body.transform_keys(&:to_s)
    end
  end
end
