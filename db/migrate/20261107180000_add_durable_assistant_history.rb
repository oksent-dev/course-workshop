class AddDurableAssistantHistory < ActiveRecord::Migration[8.1]
  def change
    add_reference :conversations, :course, foreign_key: true
    add_reference :conversations, :learner_profile, foreign_key: true
    add_column :conversations, :mode, :string, null: false, default: "tutor"
    add_column :conversations, :legacy, :boolean, null: false, default: false
    change_column_null :conversations, :lesson_id, true
    change_column_null :conversations, :browser_key, true
    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE conversations SET course_id = lessons.course_id, legacy = TRUE
          FROM lessons WHERE conversations.lesson_id = lessons.id
        SQL
      end
    end
    change_column_null :conversations, :course_id, false
    add_index :conversations, [ :course_id, :learner_profile_id, :mode ],
      unique: true, where: "legacy = FALSE", name: "unique_course_assistant_owner"
    add_check_constraint :conversations, "mode IN ('tutor', 'editor')", name: "conversations_valid_mode"
    add_check_constraint :conversations, "legacy OR learner_profile_id IS NOT NULL", name: "conversations_have_owner"

    create_table :ai_runs do |t|
      t.references :subject, polymorphic: true, null: false
      t.string :operation_key, null: false
      t.string :job_id, null: false
      t.string :status, null: false, default: "running"
      t.string :thread_id
      t.string :turn_id
      t.datetime :submitted_at
      t.datetime :lease_until, null: false
      t.integer :recovery_attempts, null: false, default: 0
      t.jsonb :item_ids, null: false, default: []
      t.string :error_code
      t.boolean :thread_replaced, null: false, default: false
      t.timestamps
    end
    add_index :ai_runs, [ :subject_type, :subject_id, :operation_key ], unique: true
    add_index :ai_runs, [ :status, :lease_until ]
    add_check_constraint :ai_runs,
      "status IN ('running', 'recovering', 'completed', 'failed', 'cancelled', 'uncertain')", name: "ai_runs_valid_status"

    %i[exchanges course_generations course_cover_generations].each do |table|
      add_column table, :enqueued_job_id, :string
      add_column table, :enqueued_at, :datetime
    end
    remove_check_constraint :exchanges, name: "exchanges_valid_status"
    add_check_constraint :exchanges,
      "status IN ('queued', 'running', 'recovering', 'completed', 'failed', 'cancelled', 'uncertain')", name: "exchanges_valid_status"
    remove_index :exchanges, name: "one_pending_exchange_per_conversation"
    add_index :exchanges, :conversation_id, unique: true,
      where: "status IN ('queued', 'running', 'recovering')", name: "one_pending_exchange_per_conversation"
  end
end
