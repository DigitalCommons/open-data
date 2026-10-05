# Builds a MykoMaps dataset zip from a project's unified CSV and its map
# config, as data-pipelines does (merge-mykomap-config, `dataset import`,
# then copy about.md and assets/), and archives it:
#
#   <builds_root>/<project-key>/datasets/<YYYY-MM-DD_HHMMSS>/dataset.zip
class ProjectDatasetBuilder
  attr_reader :dataset, :project

  def initialize(dataset, map_config: MapConfig.for(dataset.project.key), now: Time.current)
    @dataset = dataset
    @project = dataset.project
    @map_config = map_config
    @now = now
  end

  def call
    dataset.update!(status: :running, started_at: Time.current)
    csv = dataset.project_build.csv_path or return finish(:failed, "The unified CSV build has no unified.csv.\n")
    return finish(:failed, "#{project.key} has no map config.\n") unless @map_config

    merged = @map_config.config
    config = Mykomap::Config.parse(merged)
    archive = archive_dir
    Dir.mktmpdir("dataset") do |tmp|
      out = File.join(tmp, "dataset") # the writer creates its output dir
      stats = Mykomap::DatasetBuilder.build_dataset_from_csv(config, csv, out, ->(message) { dataset.append_log("#{message}\n") })
      File.write(File.join(out, "config.json"), MapConfig.json_text(merged))
      FileUtils.cp(@map_config.about_path, File.join(out, "about.md")) if @map_config.about_path.file?
      copy_assets(out)
      Mykomap::Zip.zip_dir(out, File.join(archive, "dataset.zip"))
      dataset.item_count = stats.written
      dataset.append_log("Built #{stats.written} items from #{File.basename(csv)}" \
        "#{"; #{stats.errors.length} rows skipped (duplicate IDs)" if stats.errors.any?}.\n")
    end
    finish(:succeeded)
  rescue StandardError => e
    finish(:failed, "#{e.class}: #{e.message}\n")
  end

  private

  def copy_assets(out)
    @map_config.asset_files.each do |file|
      target = File.join(out, "assets", file.relative_path_from(@map_config.assets_dir).to_s)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.cp(file, target)
    end
  end

  def archive_dir
    dir = OpenData.builds_root + project.key + "datasets" + @now.strftime("%Y-%m-%d_%H%M%S")
    dir = Pathname.new("#{dir}-#{dataset.id}") if dir.exist?
    FileUtils.mkdir_p(dir)
    dataset.archive_path = dir.to_s
    dir.to_s
  end

  def finish(status, message = nil)
    dataset.append_log(message) if message
    dataset.update!(status: status, finished_at: Time.current)
    dataset
  end
end
