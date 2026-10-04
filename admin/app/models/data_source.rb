class DataSource < ApplicationRecord
  has_many :project_sources, dependent: :destroy
  has_many :projects, through: :project_sources
  has_many :download_runs, dependent: :destroy

  # auto: has a downloader script, can be fetched on a schedule
  # manual: data must be uploaded by hand before processing
  enum :kind, { auto: 0, manual: 1 }

  validates :directory, presence: true, uniqueness: true,
    format: { with: /\A[\w.-]+\z/, message: "must be a plain directory name" }
  validates :name, presence: true
  validate :schedule_must_be_valid_cron

  scope :enabled, -> { where(enabled: true) }

  # Sources live on prod-2/dev-2 at transition time (see TRANSITION.md); they
  # keep the legacy 10-minute schedule when first seeded.
  LEGACY_LIVE = %w[ ica newbridge mersey-green deep-adaptation dotcoop workers-coop ].freeze
  LEGACY_SCHEDULE = "*/10 * * * *".freeze

  # Curated origin/processing summaries, applied by sync_from_repo!.
  DETAILS_FILE = "db/data_source_details.yml".freeze

  def self.source_details
    path = Rails.root.join(DETAILS_FILE)
    path.file? ? YAML.load_file(path) : {}
  end

  # Register any repo source directories not yet known and fill in curated
  # details. Existing records only gain description/download_url when blank,
  # so edits made in the UI survive re-seeding (seeds run on every start).
  def self.sync_from_repo!(details: source_details)
    OpenData.source_directories.each do |dir|
      source = find_or_initialize_by(directory: dir)
      if source.new_record?
        source.assign_attributes(
          name: dir.tr("-", " ").split.map(&:capitalize).join(" "),
          kind: (OpenData.root + dir + "downloader").file? ? :auto : :manual,
          enabled: LEGACY_LIVE.include?(dir),
          schedule: LEGACY_LIVE.include?(dir) ? LEGACY_SCHEDULE : nil
        )
      end
      info = details[dir] || {}
      source.description = info["description"] if source.description.blank?
      source.download_url = info["download_url"] if source.download_url.blank?
      source.save! if source.new_record? || source.changed?
    end
  end

  def source_dir
    OpenData.root + directory
  end

  def cron
    return nil if schedule.blank?
    Fugit.parse_cron(schedule)
  end

  def last_run
    download_runs.order(created_at: :desc).first
  end

  def last_completed_run
    download_runs.completed.order(created_at: :desc).first
  end

  def last_succeeded_run
    download_runs.succeeded.order(created_at: :desc).first
  end

  def last_downloaded_at
    last_completed_run&.finished_at
  end

  def last_processed_at
    last_succeeded_run&.finished_at
  end

  def latest_standard_csv_path
    last_succeeded_run&.standard_csv_path
  end

  def running?
    download_runs.exists?(status: %i[queued running])
  end

  # A scheduled run is due when the most recent cron fire time has passed
  # with no run started since.
  def due?(now = Time.current)
    return false unless enabled? && auto? && cron
    prev = cron.previous_time(now)
    return false unless prev
    last = download_runs.maximum(:created_at)
    last.nil? || last < prev.to_t
  end

  # Overdue: enabled, on a schedule, but the last completed download predates
  # the last-but-one cron fire (i.e. at least one full cycle has been missed).
  def overdue?(now = Time.current)
    return false unless enabled? && auto? && cron
    prev = cron.previous_time(now)
    return false unless prev
    prev_prev = cron.previous_time(prev.to_t - 1)
    return false unless prev_prev
    last_downloaded_at.nil? || last_downloaded_at < prev_prev.to_t
  end

  private

  def schedule_must_be_valid_cron
    if schedule.present? && Fugit.parse_cron(schedule).nil?
      errors.add(:schedule, "is not a valid cron expression")
    elsif enabled? && auto? && schedule.blank?
      errors.add(:schedule, "is required to enable a scheduled source")
    end
  end
end
