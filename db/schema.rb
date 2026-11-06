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

ActiveRecord::Schema[8.1].define(version: 2026_11_06_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_categories_on_name", unique: true
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "lesson_id", null: false
    t.string "browser_key", null: false
    t.string "runtime_thread_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lesson_id", "browser_key"], name: "index_conversations_on_lesson_id_and_browser_key", unique: true
  end

  create_table "courses", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.string "language", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_courses_on_category_id"
    t.index ["slug"], name: "index_courses_on_slug", unique: true
  end

  create_table "exchanges", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.string "request_key", null: false
    t.text "question", null: false
    t.text "answer"
    t.jsonb "lesson_context", null: false
    t.string "locale", null: false
    t.string "status", default: "queued", null: false
    t.string "error_code"
    t.datetime "cancel_requested_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "request_key"], name: "index_exchanges_on_conversation_id_and_request_key", unique: true
    t.index ["conversation_id"], name: "index_exchanges_on_conversation_id"
    t.index ["conversation_id"], name: "one_pending_exchange_per_conversation", unique: true, where: "((status)::text = ANY ((ARRAY['queued'::character varying, 'running'::character varying])::text[]))"
    t.check_constraint "char_length(question) >= 1 AND char_length(question) <= 4000", name: "exchanges_question_length"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying]::text[])", name: "exchanges_valid_status"
  end

  create_table "lesson_images", force: :cascade do |t|
    t.bigint "lesson_id", null: false
    t.string "key", null: false
    t.text "alt_text", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lesson_id", "key"], name: "index_lesson_images_on_lesson_id_and_key", unique: true
  end

  create_table "lessons", force: :cascade do |t|
    t.bigint "course_id", null: false
    t.integer "position", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["course_id", "position"], name: "index_lessons_on_course_id_and_position", unique: true
    t.check_constraint "\"position\" > 0", name: "lessons_positive_position"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "conversations", "lessons"
  add_foreign_key "courses", "categories"
  add_foreign_key "exchanges", "conversations"
  add_foreign_key "lesson_images", "lessons"
  add_foreign_key "lessons", "courses"
end
