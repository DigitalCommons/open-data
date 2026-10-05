class CreateSecrets < ActiveRecord::Migration[8.1]
  def change
    create_table :secrets do |t|
      t.string :key, null: false
      t.text :value, null: false
      t.boolean :from_env, null: false, default: false

      t.timestamps
    end
    add_index :secrets, :key, unique: true
  end
end
