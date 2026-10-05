class AddRowCountToDownloadRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :download_runs, :row_count, :integer
  end
end
