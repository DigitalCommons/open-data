module ApplicationHelper
  STATUS_STYLES = {
    "queued" => "bg-slate-100 text-slate-700",
    "running" => "bg-sky-100 text-sky-800",
    "succeeded" => "bg-emerald-100 text-emerald-800",
    "no_changes" => "bg-slate-100 text-slate-600",
    "failed" => "bg-rose-100 text-rose-800"
  }.freeze

  def status_badge(run)
    return content_tag(:span, "never run", class: "inline-flex rounded-full px-2 py-0.5 text-xs font-medium bg-slate-100 text-slate-500") if run.nil?
    style = STATUS_STYLES.fetch(run.status, STATUS_STYLES["queued"])
    content_tag(:span, run.status.humanize.downcase, class: "inline-flex rounded-full px-2 py-0.5 text-xs font-medium #{style}")
  end

  CATEGORY_STYLES = {
    "mykomaps_v4" => "bg-emerald-100 text-emerald-800",
    "mykomaps_v3" => "bg-sky-100 text-sky-800",
    "legacy" => "bg-slate-100 text-slate-600"
  }.freeze

  def category_badge(project)
    content_tag(:span, project.category_label, class: "inline-flex rounded-full px-2 py-0.5 text-xs font-medium #{CATEGORY_STYLES.fetch(project.category)}")
  end

  def kind_badge(source)
    if source.auto?
      content_tag(:span, "scheduled", class: "inline-flex rounded-full px-2 py-0.5 text-xs font-medium bg-indigo-100 text-indigo-800")
    else
      content_tag(:span, "manual upload", class: "inline-flex rounded-full px-2 py-0.5 text-xs font-medium bg-amber-100 text-amber-800")
    end
  end

  # Age of the last download, coloured by staleness.
  def download_age(source)
    at = source.last_downloaded_at
    return content_tag(:span, "never", class: "text-slate-400") if at.nil?
    classes =
      if source.overdue?
        "text-rose-600 font-medium"
      elsif at > 1.day.ago
        "text-emerald-700"
      else
        "text-slate-600"
      end
    content_tag(:span, "#{time_ago_in_words(at)} ago", class: classes, title: at.to_fs(:long))
  end

  def format_duration(seconds)
    return "-" if seconds.nil?
    seconds < 60 ? "#{seconds.round(1)}s" : "#{(seconds / 60).floor}m #{(seconds % 60).round}s"
  end
end
