module ApplicationHelper
  APP_NAME = "MykoMaps OpenData".freeze

  # The release being run: CloudronManifest.json's version, which the
  # Docker image carries at /app/code. nil if the file cannot be read.
  APP_VERSION = begin
    JSON.parse(File.read(Rails.root.join("../CloudronManifest.json"))).fetch("version")
  rescue StandardError
    nil
  end

  STATUS_STYLES = {
    "queued" => "run",
    "running" => "run",
    "succeeded" => "ok",
    "no_changes" => "idle",
    "failed" => "bad"
  }.freeze

  def page_title(title = nil)
    [ title, APP_NAME ].compact.join(" - ")
  end

  def status_badge(run)
    return content_tag(:span, "never run", class: "pill idle") if run.nil?
    content_tag(:span, run.status.humanize.downcase, class: "pill #{STATUS_STYLES.fetch(run.status, 'run')}")
  end

  def category_badge(project)
    content_tag(:span, project.category_label, class: [ "tag", ("legacy" if project.legacy?) ])
  end

  def kind_label(source)
    source.auto? ? "Scheduled" : "Manual upload"
  end

  def kind_badge(source)
    content_tag(:span, kind_label(source), class: "kind")
  end

  # Age of the last download, coloured by staleness.
  def download_age(source)
    at = source.last_downloaded_at
    return content_tag(:span, "never", class: "age-never") if at.nil?
    css =
      if source.overdue? then "age-overdue"
      elsif at > 1.day.ago then "age-fresh"
      else "age-old"
      end
    content_tag(:span, "#{time_ago_in_words(at)} ago", class: css, title: at.to_fs(:long))
  end

  # Rows added, removed and changed, coloured; "-" when not recorded.
  def row_changes(record)
    return "-" if record.rows_added.nil?
    content_tag(:span, class: "diff") do
      safe_join([
        content_tag(:span, "+#{record.rows_added}", class: "a"),
        content_tag(:span, "-#{record.rows_removed}", class: "r"),
        content_tag(:span, "~#{record.rows_changed}", class: "c")
      ])
    end
  end

  # A cron schedule with any time zone on its own muted line.
  def schedule_cell(schedule)
    return "-" if schedule.blank?
    fields = schedule.split
    cron = fields.first(5).join(" ")
    zone = fields.drop(5).join(" ")
    zone.present? ? safe_join([ cron, content_tag(:small, zone, class: "tz") ]) : cron
  end

  # Escapes text and links any http(s) URLs in it.
  def link_urls(text)
    safe_join(text.to_s.split(%r{(https?://[^\s)]+)}).map.with_index do |part, index|
      index.odd? ? link_to(part, part, class: "link", target: "_blank", rel: "noopener") : part
    end)
  end

  def format_duration(seconds)
    return "-" if seconds.nil?
    seconds < 60 ? "#{seconds.round(1)}s" : "#{(seconds / 60).floor}m #{(seconds % 60).round}s"
  end
end
