namespace :row_stamps do
  desc "Date the rows of each source's latest download from its archived history"
  task backfill: :environment do
    DataSource.order(:directory).each do |source|
      puts "#{source.directory}: #{RowStamps::Backfill.new(source).call.to_s.tr('_', ' ')}"
    end
  end
end
