require "zip"

module DataBuilder
  # Runs the build pipeline for one Build: value-map rewrite -> geocode ->
  # dataset write -> zip. Ported from the monolith's POST /admin/build
  # handler (routesBuilder.ts), with the dataset delivered as a zip download
  # instead of being installed into a served datasets dir.
  class BuildJob < ApplicationJob
    queue_as :default

    def perform(build)
      build.update!(status: :running)
      req = build.request_data
      config = Mykomap::Config.parse(req["config"])

      staged_csv = DataBuilder.uploads_dir + "#{build.csv_id}.csv"
      # Intermediates live in a per-build work dir so concurrent builds of
      # the same staged CSV can't clobber each other's files.
      work_dir = DataBuilder.builds_dir + ".build-#{build.id}"
      mapped_csv = work_dir + "mapped.csv"
      geocoded_csv = work_dir + "geocoded.csv"
      tmp_dir = work_dir + "dataset"
      FileUtils.rm_rf(work_dir)
      FileUtils.mkdir_p(work_dir)

      build_csv = staged_csv
      geocode_message = ""

      value_maps = req["valueMaps"] || {}
      if value_maps.any?
        CsvTransformer.transform(build_csv, mapped_csv, value_maps, CsvTransformer.multi_value_headers(config))
        build_csv = mapped_csv
      end

      geocode = req["geocode"] || {}
      if geocode["template"].to_s.strip != ""
        stats = Geocoder.geocode_csv(build_csv, geocoded_csv, geocode)
        build_csv = geocoded_csv
        geocode_message = " #{stats.message}"
      end

      stats = Mykomap::DatasetBuilder.build_dataset_from_csv(config, build_csv.to_s, tmp_dir.to_s)

      File.write(tmp_dir + "config.json", Mykomap::JsJson.pretty_generate(config) + "\n")
      # Always written: Mykomap::Dataset (and the monolith) read it
      # unconditionally, so a dataset without it fails to load.
      about = req["about"]
      File.write(tmp_dir + "about.md", about.is_a?(String) ? about : "")
      File.write(tmp_dir + "meta.json", JSON.pretty_generate({
        displayName: build.display_name,
        createdAt: Time.current.iso8601,
        project: req["project"].presence,
        subProject: req["subProject"].presence,
        source: { type: "csv-build", filename: build.csv_filename }
      }.compact))
      FileUtils.cp(staged_csv, tmp_dir + "source.csv")

      Mykomap::Zip.zip_dir(tmp_dir, build.zip_path)

      skipped = stats.errors.length
      build.update!(
        status: :succeeded,
        message: "dataset '#{build.name}' built: #{stats.written} items." +
          (skipped.positive? ? " #{skipped} row(s) skipped (duplicate IDs)." : "") +
          geocode_message
      )
    rescue => e
      build.update!(status: :failed, error: "failed to build dataset: #{e.message}")
    ensure
      FileUtils.rm_rf(work_dir) if work_dir
    end
  end
end
