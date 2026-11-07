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

ActiveRecord::Schema[8.1].define(version: 2026_11_07_190000) do
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

  create_table "ai_runs", force: :cascade do |t|
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.string "operation_key", null: false
    t.string "job_id", null: false
    t.string "status", default: "running", null: false
    t.string "thread_id"
    t.string "turn_id"
    t.datetime "submitted_at"
    t.datetime "lease_until", null: false
    t.integer "recovery_attempts", default: 0, null: false
    t.jsonb "item_ids", default: [], null: false
    t.string "error_code"
    t.boolean "thread_replaced", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status", "lease_until"], name: "index_ai_runs_on_status_and_lease_until"
    t.index ["subject_type", "subject_id", "operation_key"], name: "index_ai_runs_on_subject_type_and_subject_id_and_operation_key", unique: true
    t.index ["subject_type", "subject_id"], name: "index_ai_runs_on_subject"
    t.check_constraint "status::text = ANY (ARRAY['running'::character varying, 'recovering'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'uncertain'::character varying]::text[])", name: "ai_runs_valid_status"
  end

  create_table "assistant_activities", force: :cascade do |t|
    t.bigint "exchange_id", null: false
    t.bigint "course_change_id"
    t.string "key", null: false
    t.string "tool", null: false
    t.string "status", default: "running", null: false
    t.string "error_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["course_change_id"], name: "index_assistant_activities_on_course_change_id"
    t.index ["exchange_id", "key"], name: "index_assistant_activities_on_exchange_id_and_key", unique: true
    t.index ["exchange_id"], name: "index_assistant_activities_on_exchange_id"
    t.check_constraint "status::text = ANY (ARRAY['running'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "assistant_activities_valid_status"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_categories_on_normalized_name", unique: true
    t.index ["name"], name: "index_categories_on_name", unique: true
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "lesson_id"
    t.string "browser_key"
    t.string "runtime_thread_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "course_id", null: false
    t.bigint "learner_profile_id"
    t.string "mode", default: "tutor", null: false
    t.boolean "legacy", default: false, null: false
    t.index ["course_id", "learner_profile_id", "mode"], name: "unique_course_assistant_owner", unique: true, where: "(legacy = false)"
    t.index ["course_id"], name: "index_conversations_on_course_id"
    t.index ["learner_profile_id"], name: "index_conversations_on_learner_profile_id"
    t.index ["lesson_id", "browser_key"], name: "index_conversations_on_lesson_id_and_browser_key", unique: true
    t.check_constraint "legacy OR learner_profile_id IS NOT NULL", name: "conversations_have_owner"
    t.check_constraint "mode::text = ANY (ARRAY['tutor'::character varying, 'editor'::character varying]::text[])", name: "conversations_valid_mode"
  end

  create_table "course_changes", force: :cascade do |t|
    t.bigint "course_id", null: false
    t.bigint "exchange_id", null: false
    t.bigint "undo_of_id"
    t.string "operation", null: false
    t.integer "revision", null: false
    t.jsonb "before_state", null: false
    t.jsonb "after_state", null: false
    t.datetime "undone_at"
    t.uuid "undo_key", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["course_id", "revision"], name: "index_course_changes_on_course_id_and_revision", unique: true
    t.index ["course_id"], name: "index_course_changes_on_course_id"
    t.index ["exchange_id"], name: "index_course_changes_on_exchange_id"
    t.index ["undo_of_id"], name: "index_course_changes_on_undo_of_id"
  end

  create_table "course_cover_generations", force: :cascade do |t|
    t.bigint "course_id", null: false
    t.string "status", default: "queued", null: false
    t.integer "attempt", default: 1, null: false
    t.string "error_code"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "enqueued_job_id"
    t.datetime "enqueued_at"
    t.index ["course_id"], name: "index_course_cover_generations_on_course_id", unique: true
    t.check_constraint "attempt > 0", name: "covers_positive_attempt"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'running'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "covers_valid_status"
  end

  create_table "course_generations", force: :cascade do |t|
    t.bigint "course_id", null: false
    t.uuid "request_key", null: false
    t.text "topic", null: false
    t.string "language", null: false
    t.integer "lesson_count"
    t.string "status", default: "queued", null: false
    t.integer "attempt", default: 1, null: false
    t.jsonb "plan", default: [], null: false
    t.string "token_digest"
    t.string "error_code"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stage", default: "planning", null: false
    t.integer "step", default: 0, null: false
    t.integer "current_position"
    t.datetime "plan_approved_at"
    t.string "activity"
    t.datetime "activity_at"
    t.text "illustration_prompt"
    t.string "illustration_alt"
    t.string "enqueued_job_id"
    t.datetime "enqueued_at"
    t.jsonb "approved_plan", default: [], null: false
    t.index ["course_id"], name: "index_course_generations_on_course_id", unique: true
    t.index ["request_key"], name: "index_course_generations_on_request_key", unique: true
    t.check_constraint "(lesson_count IS NULL OR lesson_count >= 1 AND lesson_count <= 60) AND attempt > 0", name: "generations_valid_limits"
    t.check_constraint "(stage::text = ANY (ARRAY['planning'::character varying::text, 'writing'::character varying::text, 'illustrating'::character varying::text, 'checking'::character varying::text])) AND step >= 0 AND (current_position IS NULL OR current_position >= 1 AND current_position <= 60)", name: "generations_valid_step"
    t.check_constraint "language::text = ANY (ARRAY['pl'::character varying::text, 'en'::character varying::text])", name: "generations_valid_language"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'running'::character varying::text, 'awaiting_approval'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'cancelled'::character varying::text])", name: "generations_valid_status"
  end

  create_table "courses", force: :cascade do |t|
    t.bigint "category_id", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.string "language", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "draft", null: false
    t.integer "revision", default: 0, null: false
    t.index ["category_id"], name: "index_courses_on_category_id"
    t.index ["slug"], name: "index_courses_on_slug", unique: true
    t.check_constraint "revision >= 0", name: "courses_nonnegative_revision"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'published'::character varying::text])", name: "courses_valid_status"
  end

  create_table "draft_cover_requests", force: :cascade do |t|
    t.bigint "course_id", null: false
    t.bigint "exchange_id", null: false
    t.bigint "course_change_id"
    t.text "prompt", null: false
    t.integer "expected_revision", null: false
    t.string "status", default: "queued", null: false
    t.string "error_code"
    t.datetime "expires_at"
    t.string "enqueued_job_id"
    t.datetime "enqueued_at"
    t.uuid "retry_key", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["course_change_id"], name: "index_draft_cover_requests_on_course_change_id"
    t.index ["course_id"], name: "index_draft_cover_requests_on_course_id"
    t.index ["course_id"], name: "one_pending_draft_cover", unique: true, where: "((status)::text = ANY ((ARRAY['queued'::character varying, 'running'::character varying, 'recovering'::character varying])::text[]))"
    t.index ["exchange_id"], name: "index_draft_cover_requests_on_exchange_id"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying, 'running'::character varying, 'recovering'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'uncertain'::character varying]::text[])", name: "draft_cover_requests_valid_status"
  end

  create_table "draft_operations", force: :cascade do |t|
    t.uuid "request_key", null: false
    t.string "fingerprint", null: false
    t.jsonb "result", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["request_key"], name: "index_draft_operations_on_request_key", unique: true
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
    t.string "enqueued_job_id"
    t.datetime "enqueued_at"
    t.string "editor_token_digest"
    t.datetime "editor_expires_at"
    t.index ["conversation_id", "request_key"], name: "index_exchanges_on_conversation_id_and_request_key", unique: true
    t.index ["conversation_id"], name: "index_exchanges_on_conversation_id"
    t.index ["conversation_id"], name: "one_pending_exchange_per_conversation", unique: true, where: "((status)::text = ANY ((ARRAY['queued'::character varying, 'running'::character varying, 'recovering'::character varying])::text[]))"
    t.check_constraint "char_length(question) >= 1 AND char_length(question) <= 4000", name: "exchanges_question_length"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying, 'running'::character varying, 'recovering'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying, 'uncertain'::character varying]::text[])", name: "exchanges_valid_status"
  end

  create_table "learner_profiles", force: :cascade do |t|
    t.string "key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_learner_profiles_on_key", unique: true
  end

  create_table "lesson_images", force: :cascade do |t|
    t.bigint "lesson_id", null: false
    t.string "key", null: false
    t.text "alt_text", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lesson_id", "key"], name: "index_lesson_images_on_lesson_id_and_key", unique: true
  end

  create_table "lesson_progresses", force: :cascade do |t|
    t.bigint "learner_profile_id", null: false
    t.bigint "lesson_id", null: false
    t.datetime "last_opened_at", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["learner_profile_id", "lesson_id"], name: "index_lesson_progresses_on_learner_profile_id_and_lesson_id", unique: true
    t.index ["lesson_id"], name: "index_lesson_progresses_on_lesson_id"
  end

  create_table "lessons", force: :cascade do |t|
    t.bigint "course_id", null: false
    t.integer "position", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "archived_at"
    t.index ["course_id", "position"], name: "index_lessons_on_course_id_and_position", unique: true, where: "(archived_at IS NULL)"
    t.check_constraint "\"position\" > 0", name: "lessons_positive_position"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "assistant_activities", "course_changes"
  add_foreign_key "assistant_activities", "exchanges"
  add_foreign_key "conversations", "courses"
  add_foreign_key "conversations", "learner_profiles"
  add_foreign_key "conversations", "lessons"
  add_foreign_key "course_changes", "course_changes", column: "undo_of_id"
  add_foreign_key "course_changes", "courses"
  add_foreign_key "course_changes", "exchanges"
  add_foreign_key "course_cover_generations", "courses"
  add_foreign_key "course_generations", "courses"
  add_foreign_key "courses", "categories"
  add_foreign_key "draft_cover_requests", "course_changes"
  add_foreign_key "draft_cover_requests", "courses"
  add_foreign_key "draft_cover_requests", "exchanges"
  add_foreign_key "exchanges", "conversations"
  add_foreign_key "lesson_images", "lessons"
  add_foreign_key "lesson_progresses", "learner_profiles"
  add_foreign_key "lesson_progresses", "lessons"
  add_foreign_key "lessons", "courses"
end
