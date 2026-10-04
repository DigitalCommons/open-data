class CreateProjectBuilds < ActiveRecord::Migration[8.1]
  def change
    create_table :project_builds do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.integer :status, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.text :log
      t.string :archive_path
      t.integer :row_count
      t.integer :merged_count
      t.integer :rows_added
      t.integer :rows_removed
      t.integer :rows_changed
      t.text :diff_summary

      t.timestamps
    end
  end
end
