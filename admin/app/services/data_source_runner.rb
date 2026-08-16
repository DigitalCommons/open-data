require "open3"

# Executes one DownloadRun: fetches (or installs the uploaded file), converts
# with seod, archives the results into a dated folder and records a diff
# against the previous download.
class DataSourceRunner
  NO_CHANGES_EXIT = 100

  attr_reader :run, :source

  def initialize(run)
    @run = run
    @source = run.data_source
  end

  def call
    run.update!(status: :running, started_at: Time.current)

    unless source.project_dir.directory?
      return finish(:failed, "Project directory not found: #{source.project_dir}\n")
    end

    previous_csv = source.latest_standard_csv_path

    install_upload if run.upload?

    if (source.project_dir + "Gemfile").file?
      return finish(:failed) unless execute([ "bundle", "install", "--quiet" ]).success?
    end

    unless run.upload?
      status = seod("download")
      return finish(:failed) unless status.exitstatus.in?([ 0, NO_CHANGES_EXIT ])
      if status.exitstatus == NO_CHANGES_EXIT
        run.append_log("No new data available.\n")
        return finish(:no_changes)
      end
    end

    return finish(:failed) unless seod("convert").success?

    standard_csv = source.project_dir + "generated-data/standard.csv"
    unless standard_csv.file?
      return finish(:failed, "Conversion produced no #{standard_csv}\n")
    end

    run.update!(archive_path: RunArchiver.new(run).call.to_s)
    diff = record_diff(previous_csv)

    # A download that converts to an identical standard.csv is a duplicate:
    # keep the run line but not the files. The byte comparison guards against
    # a misleading zero diff (duplicate/blank Identifiers collapse in CsvDiff).
    if previous_csv && diff && !run.changes? &&
        run.standard_csv_path && FileUtils.identical?(previous_csv, run.standard_csv_path)
      FileUtils.remove_entry(run.archive_path)
      run.update!(archive_path: nil)
      run.append_log("Converted output identical to previous download; archive discarded.\n")
      return finish(:no_changes)
    end

    finish(:succeeded)
  rescue => e
    finish(:failed, "Error: #{e.class}: #{e.message}\n")
  end

  private

  def finish(status, message = nil)
    run.append_log(message) if message
    run.update!(status: status, finished_at: Time.current)
    run
  end

  # Copy the uploaded file into original-data/ so the converter picks it up.
  def install_upload
    raise "No uploaded file recorded" if run.uploaded_file_path.blank?
    raise "Uploaded file missing: #{run.uploaded_file_path}" unless File.file?(run.uploaded_file_path)

    original_data = source.project_dir + "original-data"
    FileUtils.mkdir_p(original_data)
    # The convert stage only reads the conf's ORIGINAL_CSV filename, so the
    # upload must be installed under that name, not the browser's.
    target = original_csv_name
    FileUtils.cp(run.uploaded_file_path, original_data + target)
    run.append_log("Installed uploaded file #{run.uploaded_filename} as #{original_data + target}\n")
  end

  def seod(command)
    execute(OpenData.seod_wrapper.split + [ "seod", command ])
  end

  def execute(argv)
    run.append_log("$ #{argv.join(' ')}\n")
    output, status = Open3.capture2e(subprocess_env, *argv,
      unsetenv_others: true, chdir: source.project_dir.to_s)
    run.append_log(output)
    run.append_log("(exit #{status.exitstatus})\n")
    run.exit_code = status.exitstatus
    run.save!
    status
  end

  # The app runs under its own bundler; the project must resolve its own
  # Gemfile with the system bundler, so strip bundler and ruby load-path
  # leakage from the child env, including the vendored-gem bin dirs bundler
  # prepends to PATH (otherwise the child runs the app's bundler version).
  def subprocess_env
    env = ENV.to_h.reject do |key, _|
      key.start_with?("BUNDLE_", "BUNDLER_", "GEM_") || key.in?(%w[ RUBYOPT RUBYLIB ])
    end
    if defined?(Bundler) && env["PATH"]
      bundle_root = Bundler.bundle_path.to_s
      env["PATH"] = env["PATH"].split(File::PATH_SEPARATOR)
        .reject { |dir| dir.start_with?(bundle_root) }
        .join(File::PATH_SEPARATOR)
    end
    # Without SEOD_CONFIG seod falls back to local.conf/default.conf, the dev
    # config (dev endpoints, IP-locked download URLs). Prefer production.conf
    # where the project has one; an explicit SEOD_CONFIG env var still wins.
    if env["SEOD_CONFIG"].blank? && (source.project_dir + "production.conf").file?
      env["SEOD_CONFIG"] = "production.conf"
    end
    env
  end

  # The name the convert stage reads from original-data/, from the same conf
  # file seod will use (ORIGINAL_CSV; the gem's default is original.csv).
  def original_csv_name
    names = subprocess_env["SEOD_CONFIG"] || "{local,default}.conf"
    conf = Dir.glob(names, base: source.project_dir.to_s).first
    if conf && (path = source.project_dir + conf).file?
      match = path.read[/^\s*ORIGINAL_CSV\s*=\s*(\S+)/, 1]
      return match if match
    end
    "original.csv"
  end

  def record_diff(previous_csv)
    new_csv = run.standard_csv_path
    return nil unless new_csv

    diff = CsvDiff.call(previous_csv, new_csv)
    File.write(File.join(run.archive_path, "diff.txt"), diff.detail)
    run.update!(
      rows_added: diff.added,
      rows_removed: diff.removed,
      rows_changed: diff.changed,
      diff_summary: diff.summary
    )
    diff
  end
end
