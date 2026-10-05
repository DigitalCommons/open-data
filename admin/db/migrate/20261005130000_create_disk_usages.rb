class CreateDiskUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :disk_usages do |t|
      t.bigint :downloads_bytes, null: false, default: 0
      t.bigint :builds_bytes, null: false, default: 0
      t.datetime :measured_at, null: false

      t.timestamps
    end
  end
end
