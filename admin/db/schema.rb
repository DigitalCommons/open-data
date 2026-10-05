# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_05_140000) do
  create_table "data_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "directory", null: false
    t.string "download_url"
    t.boolean "enabled", default: false, null: false
    t.integer "kind", default: 0, null: false
    t.string "name", null: false
    t.string "schedule"
    t.datetime "updated_at", null: false
    t.index ["directory"], name: "index_data_sources_on_directory", unique: true
  end

  create_table "disk_usages", force: :cascade do |t|
    t.bigint "builds_bytes", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "downloads_bytes", default: 0, null: false
    t.datetime "measured_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "download_runs", force: :cascade do |t|
    t.string "archive_path"
    t.datetime "created_at", null: false
    t.integer "data_source_id", null: false
    t.text "diff_summary"
    t.integer "exit_code"
    t.datetime "finished_at"
    t.text "log"
    t.integer "row_count"
    t.integer "rows_added"
    t.integer "rows_changed"
    t.integer "rows_removed"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.integer "triggered_by", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "uploaded_file_path"
    t.string "uploaded_filename"
    t.index ["data_source_id", "created_at"], name: "index_download_runs_on_data_source_id_and_created_at"
    t.index ["data_source_id"], name: "index_download_runs_on_data_source_id"
  end

  create_table "project_builds", force: :cascade do |t|
    t.string "archive_path"
    t.datetime "created_at", null: false
    t.text "diff_summary"
    t.datetime "finished_at"
    t.text "log"
    t.integer "merged_count"
    t.integer "project_id", null: false
    t.integer "row_count"
    t.integer "rows_added"
    t.integer "rows_changed"
    t.integer "rows_removed"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_project_builds_on_project_id"
  end

  create_table "project_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "data_source_id", null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["data_source_id"], name: "index_project_sources_on_data_source_id"
    t.index ["project_id", "data_source_id"], name: "index_project_sources_on_project_id_and_data_source_id", unique: true
    t.index ["project_id"], name: "index_project_sources_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.integer "category", default: 2, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_projects_on_key", unique: true
  end

  create_table "secrets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "from_env", default: false, null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value", null: false
    t.index ["key"], name: "index_secrets_on_key", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "password_changed_at"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "download_runs", "data_sources"
  add_foreign_key "project_builds", "projects", on_delete: :cascade
  add_foreign_key "project_sources", "data_sources", on_delete: :cascade
  add_foreign_key "project_sources", "projects", on_delete: :cascade
  add_foreign_key "sessions", "users"
end
