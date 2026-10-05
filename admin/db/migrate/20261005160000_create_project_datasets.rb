class CreateProjectDatasets < ActiveRecord::Migration[8.1]
  def change
    create_table :project_datasets do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :project_build, null: false, foreign_key: { on_delete: :cascade }
      t.integer :status, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.text :log
      t.string :archive_path
      t.integer :item_count

      t.timestamps
    end
  end
end
