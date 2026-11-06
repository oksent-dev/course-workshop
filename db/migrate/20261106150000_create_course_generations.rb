class CreateCourseGenerations < ActiveRecord::Migration[8.1]
  def change
    create_table :course_generations do |t|
      t.references :course, null: false, foreign_key: true, index: { unique: true }
      t.uuid :request_key, null: false, index: { unique: true }
      t.text :topic, null: false
      t.string :language, null: false
      t.integer :lesson_count, null: false
      t.string :status, null: false, default: "queued"
      t.integer :attempt, null: false, default: 1
      t.jsonb :plan, null: false, default: []
      t.string :token_digest
      t.string :error_code
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_check_constraint :course_generations, "status IN ('queued', 'running', 'completed', 'failed', 'cancelled')", name: "generations_valid_status"
    add_check_constraint :course_generations, "lesson_count BETWEEN 3 AND 6 AND attempt > 0", name: "generations_valid_limits"
    add_check_constraint :course_generations, "language IN ('pl', 'en')", name: "generations_valid_language"
  end
end
