class CreateDownloadRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :download_runs do |t|
      t.references :data_source, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.integer :triggered_by, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :exit_code
      t.text :log
      t.string :archive_path
      t.string :uploaded_filename
      t.string :uploaded_file_path
      t.integer :rows_added
      t.integer :rows_removed
      t.integer :rows_changed
      t.text :diff_summary

      t.timestamps
    end
    add_index :download_runs, [ :data_source_id, :created_at ]
  end
end
