class CreateDataBuilderTables < ActiveRecord::Migration[8.1]
  def change
    create_table :data_builder_templates do |t|
      t.string :name, null: false
      t.string :description
      t.text :state, null: false
      t.timestamps
    end
    add_index :data_builder_templates, :name, unique: true

    create_table :data_builder_builds do |t|
      t.string :name, null: false
      t.string :display_name
      t.integer :status, null: false, default: 0
      t.string :csv_id, null: false
      t.string :csv_filename
      t.text :request, null: false
      t.string :message
      t.string :error
      t.text :log
      t.timestamps
    end

    create_table :mykomap_geocode_entries do |t|
      t.string :input, null: false
      t.float :lat
      t.float :lng
      t.timestamps
    end
    add_index :mykomap_geocode_entries, :input, unique: true
  end
end
