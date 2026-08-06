class CreateDataSources < ActiveRecord::Migration[8.1]
  def change
    create_table :data_sources do |t|
      t.string :directory, null: false
      t.string :name, null: false
      t.text :description
      t.string :download_url
      t.integer :kind, null: false, default: 0
      t.boolean :enabled, null: false, default: false
      t.string :schedule

      t.timestamps
    end
    add_index :data_sources, :directory, unique: true
  end
end
