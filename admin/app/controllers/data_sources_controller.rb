class DataSourcesController < ApplicationController
  before_action :set_data_source, except: :index

  def index
    @data_sources = DataSource.order(enabled: :desc, name: :asc)
    @projects = Project.ordered
    group_sources_by_project
  end

  def show
    @download_runs = @data_source.download_runs.order(created_at: :desc).limit(50)
  end

  def edit
  end

  def update
    if @data_source.update(data_source_params)
      redirect_to @data_source, notice: "Data source updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def toggle
    if @data_source.update(enabled: !@data_source.enabled?)
      redirect_back fallback_location: data_sources_path,
        notice: "#{@data_source.name} #{@data_source.enabled? ? 'enabled' : 'disabled'}."
    else
      redirect_back fallback_location: data_sources_path,
        alert: @data_source.errors.full_messages.to_sentence
    end
  end

  # Manual "download now".
  def run
    if @data_source.manual?
      return redirect_to @data_source, alert: "This source has no downloader; upload a file instead."
    end
    if @data_source.running?
      return redirect_to @data_source, alert: "A run is already in progress."
    end
    run = @data_source.download_runs.create!(status: :queued, triggered_by: :manual)
    DataSourceRunJob.perform_later(run)
    redirect_to @data_source, notice: "Download queued."
  end

  # Manual upload of an original-data file, then process it.
  def upload
    file = params[:file]
    return redirect_to @data_source, alert: "Choose a file to upload." if file.blank?
    if @data_source.running?
      return redirect_to @data_source, alert: "A run is already in progress."
    end

    filename = File.basename(file.original_filename)
    incoming = OpenData.downloads_root + @data_source.directory + "incoming"
    FileUtils.mkdir_p(incoming)
    stored = incoming + "#{Time.current.strftime('%Y-%m-%d_%H%M%S')}-#{filename}"
    File.binwrite(stored, file.read)

    run = @data_source.download_runs.create!(
      status: :queued, triggered_by: :upload,
      uploaded_filename: filename, uploaded_file_path: stored.to_s
    )
    DataSourceRunJob.perform_later(run)
    redirect_to @data_source, notice: "Upload received; processing queued."
  end

  # Latest converted output.
  def standard_csv
    path = @data_source.latest_standard_csv_path
    return redirect_to @data_source, alert: "No converted output available yet." unless path
    send_file path, filename: "#{@data_source.directory}-standard.csv", type: "text/csv"
  end

  private

  # A source is listed under every project it belongs to, in dashboard
  # order; sources in no project are listed under "Other sources".
  def group_sources_by_project
    member_ids = ProjectSource.pluck(:project_id, :data_source_id)
      .group_by(&:first).transform_values { |pairs| pairs.map(&:last).to_set }
    @sources_by_project = @projects.to_h do |project|
      ids = member_ids.fetch(project.id, Set.new)
      [ project.id, @data_sources.select { |source| ids.include?(source.id) } ]
    end
    grouped_ids = member_ids.values.reduce(Set.new, :|)
    @other_sources = @data_sources.reject { |source| grouped_ids.include?(source.id) }
  end

  def set_data_source
    @data_source = DataSource.find(params[:id])
  end

  def data_source_params
    params.expect(data_source: [ :name, :description, :download_url, :schedule, :enabled, :kind ])
  end
end
