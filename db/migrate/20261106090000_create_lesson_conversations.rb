class CreateLessonConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :lesson, null: false, foreign_key: true, index: false
      t.string :browser_key, null: false
      t.string :runtime_thread_id
      t.timestamps
    end
    add_index :conversations, [ :lesson_id, :browser_key ], unique: true

    create_table :exchanges do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :request_key, null: false
      t.text :question, null: false
      t.text :answer
      t.jsonb :lesson_context, null: false
      t.string :locale, null: false
      t.string :status, null: false, default: "queued"
      t.string :error_code
      t.datetime :cancel_requested_at
      t.timestamps
    end
    add_index :exchanges, [ :conversation_id, :request_key ], unique: true
    add_index :exchanges, :conversation_id, unique: true,
      where: "status IN ('queued', 'running')", name: "one_pending_exchange_per_conversation"
    add_check_constraint :exchanges,
      "status IN ('queued', 'running', 'completed', 'failed', 'cancelled')", name: "exchanges_valid_status"
    add_check_constraint :exchanges, "char_length(question) BETWEEN 1 AND 4000", name: "exchanges_question_length"
  end
end
