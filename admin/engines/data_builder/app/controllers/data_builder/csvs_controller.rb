require "securerandom"

module DataBuilder
  # Staging CSVs for the builder: multipart upload, re-inspection, and
  # staging an admin data source's latest standard.csv.
  class CsvsController < ApplicationController
    # POST /csvs - multipart form with a `file` field
    def create
      DataBuilder.sweep_uploads!

      file = params[:file]
      return send_message(400, "missing CSV file") if file.blank? || !file.respond_to?(:read)

      id = SecureRandom.hex(8)
      FileUtils.mkdir_p(DataBuilder.uploads_dir)
      File.binwrite(csv_file(id), file.read)

      if File.size(csv_file(id)).zero?
        File.delete(csv_file(id))
        return send_message(400, "CSV file is empty")
      end

      stage(id, File.basename(file.original_filename))
    end

    # GET /csvs/:id - re-inspect a staged CSV
    def show
      id = params[:id]
      return send_message(400, "unknown CSV upload - please upload the CSV again") unless staged?(id)

      meta = read_meta(id)
      inspection = CsvInspector.inspect_csv(csv_file(id))
      render json: { id: id, filename: meta["filename"], uploadedAt: meta["uploadedAt"], inspection: inspection }
    end

    # GET /sources - admin data sources with a converted standard.csv
    def sources
      sources = ::DataSource.order(:name).filter_map do |source|
        path = source.latest_standard_csv_path
        next unless path
        { id: source.id, name: source.name, directory: source.directory,
          convertedAt: source.last_processed_at&.iso8601 }
      end
      render json: { sources: sources }
    end

    # POST /csvs/from_source/:data_source_id - stage a source's standard.csv
    def from_source
      DataBuilder.sweep_uploads!
      source = ::DataSource.find_by(id: params[:data_source_id])
      return send_message(404, "no such data source") unless source
      path = source.latest_standard_csv_path
      return send_message(400, "data source '#{source.name}' has no converted standard.csv yet") unless path

      id = SecureRandom.hex(8)
      FileUtils.mkdir_p(DataBuilder.uploads_dir)
      FileUtils.cp(path, csv_file(id))
      stage(id, "#{source.directory}-standard.csv")
    end

    private

    def stage(id, filename)
      skipped = CsvInspector.strip_leading_junk(csv_file(id))
      inspection = CsvInspector.inspect_csv(csv_file(id))
      raise "no rows found" if inspection["headers"].empty? || inspection["rowCount"].zero?

      File.write(meta_file(id), JSON.generate({ filename: filename, uploadedAt: Time.current.iso8601 }))
      render json: { id: id, filename: filename, skippedLeading: skipped, inspection: inspection }, status: :created
    rescue => e
      File.delete(csv_file(id)) if File.exist?(csv_file(id))
      send_message(400, "could not parse file as CSV: #{e.message}")
    end

    def csv_file(id)
      DataBuilder.uploads_dir + "#{id}.csv"
    end

    def meta_file(id)
      DataBuilder.uploads_dir + "#{id}.meta.json"
    end

    def staged?(id)
      id.to_s.match?(/\A[a-f0-9]{16}\z/) && File.exist?(csv_file(id))
    end

    def read_meta(id)
      JSON.parse(File.read(meta_file(id)))
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end
  end
end
