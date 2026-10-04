# Seeding only fills blank descriptions, so a CWM project created before
# the note was added to db/projects.yml gets it appended here, once.
class AddPriorityNoteToCwmDescription < ActiveRecord::Migration[8.1]
  NOTE = "Note: the unified CSV matches data-pipelines, including its bug that ignores the field and name priorities (data-unification.ts spreads tables instead of fieldPriorities), so merged records take each field from the first source alphabetically. To be fixed. Merged Identifiers can change between builds, as they do in data-pipelines, so the diff may report a merged organisation as removed and added.".freeze

  def up
    description = select_value("SELECT description FROM projects WHERE key = 'cwm'")
    return if description.nil? || description.include?(NOTE)

    update "UPDATE projects SET description = #{quote([ description, NOTE ].join(" "))} WHERE key = 'cwm'"
  end

  def down
  end
end
