# Run the unified CSV steps outside a build, e.g. to compare with
# data-pipelines on the same inputs:
#
#   bin/rails unified_csv:clean PROJECT=cwm INPUTS=dir OUT=dir
#     INPUTS holds <code>.csv standard CSVs; writes <code>.cleaned.csv
#   bin/rails unified_csv:unify PROJECT=cwm CLEANED=dir OUT=file.csv
#     CLEANED holds <code>.cleaned.csv
namespace :unified_csv do
  def unify_settings
    Project.find_by!(key: ENV.fetch("PROJECT")).unify_settings or abort "#{ENV['PROJECT']} has no unify settings"
  end

  desc "Clean standard CSVs named <code>.csv in INPUTS into OUT"
  task clean: :environment do
    inputs = Pathname.new(ENV.fetch("INPUTS"))
    out = Pathname.new(ENV.fetch("OUT")).tap(&:mkpath)
    unify_settings.tables.each do |table|
      count = UnifiedCsv::Cleaner.new(code: table.code, row_filter: table.row_filter)
        .clean(inputs + "#{table.code}.csv", out + "#{table.code}.cleaned.csv")
      puts "#{table.code}: #{count} rows"
    end
  end

  desc "Unify <code>.cleaned.csv files in CLEANED into OUT"
  task unify: :environment do
    settings = unify_settings
    cleaned = Pathname.new(ENV.fetch("CLEANED"))
    paths = settings.tables.to_h { |table| [ table.code, cleaned + "#{table.code}.cleaned.csv" ] }
    started = Time.current
    stats = UnifiedCsv::Unifier.new(settings, paths).unify(ENV.fetch("OUT"))
    puts "#{stats.inspect} in #{(Time.current - started).round(1)}s"
  end
end
