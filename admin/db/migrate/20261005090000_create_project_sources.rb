# Lets a source belong to several projects (e.g. dotcoop in CWM and in the
# standalone DotCoop map), replacing data_sources.project_id.
#
# On SQLite, adding or removing a column rebuilds data_sources (copy, then
# drop the old table). Foreign keys stay enforced inside the migration's
# transaction, so the drop would cascade-delete project_sources rows. The
# memberships are therefore held in memory across the rebuild and written
# while only one of the two tables exists.
class CreateProjectSources < ActiveRecord::Migration[8.1]
  def up
    pairs = select_rows("SELECT project_id, id FROM data_sources WHERE project_id IS NOT NULL")
    remove_reference :data_sources, :project, foreign_key: { on_delete: :nullify }

    create_table :project_sources do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :data_source, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
    add_index :project_sources, %i[ project_id data_source_id ], unique: true

    pairs.each do |project_id, data_source_id|
      execute <<~SQL
        INSERT INTO project_sources (project_id, data_source_id, created_at, updated_at)
        VALUES (#{Integer(project_id)}, #{Integer(data_source_id)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
    end
  end

  def down
    first_project = select_rows("SELECT data_source_id, MIN(project_id) FROM project_sources GROUP BY data_source_id")
    drop_table :project_sources

    add_reference :data_sources, :project, foreign_key: { on_delete: :nullify }
    first_project.each do |data_source_id, project_id|
      execute "UPDATE data_sources SET project_id = #{Integer(project_id)} WHERE id = #{Integer(data_source_id)}"
    end
  end
end
