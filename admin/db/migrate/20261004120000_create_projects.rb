class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.integer :category, null: false, default: 2
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :projects, :key, unique: true

    add_reference :data_sources, :project, foreign_key: { on_delete: :nullify }
  end
end
