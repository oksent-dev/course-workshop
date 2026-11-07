class AddRecoverableDraftEditing < ActiveRecord::Migration[8.1]
  def change
    add_column :lessons, :archived_at, :datetime
    remove_index :lessons, [ :course_id, :position ], unique: true
    add_index :lessons, [ :course_id, :position ], unique: true, where: "archived_at IS NULL"
    add_column :exchanges, :editor_token_digest, :string
    add_column :exchanges, :editor_expires_at, :datetime
    add_column :course_generations, :approved_plan, :jsonb, default: [], null: false
    reversible do |direction|
      direction.up { execute "UPDATE course_generations SET approved_plan = plan WHERE plan_approved_at IS NOT NULL" }
    end

    create_table :course_changes do |t|
      t.references :course, null: false, foreign_key: true
      t.references :exchange, null: false, foreign_key: true
      t.references :undo_of, foreign_key: { to_table: :course_changes }
      t.string :operation, null: false
      t.integer :revision, null: false
      t.jsonb :before_state, null: false
      t.jsonb :after_state, null: false
      t.datetime :undone_at
      t.uuid :undo_key, null: false, default: -> { "gen_random_uuid()" }
      t.timestamps
    end
    add_index :course_changes, [ :course_id, :revision ], unique: true

    create_table :assistant_activities do |t|
      t.references :exchange, null: false, foreign_key: true
      t.references :course_change, foreign_key: true
      t.string :key, null: false
      t.string :tool, null: false
      t.string :status, null: false, default: "running"
      t.string :error_code
      t.timestamps
    end
    add_index :assistant_activities, [ :exchange_id, :key ], unique: true
    add_check_constraint :assistant_activities, "status IN ('running', 'completed', 'failed')", name: "assistant_activities_valid_status"

    create_table :draft_cover_requests do |t|
      t.references :course, null: false, foreign_key: true
      t.references :exchange, null: false, foreign_key: true
      t.references :course_change, foreign_key: true
      t.text :prompt, null: false
      t.integer :expected_revision, null: false
      t.string :status, null: false, default: "queued"
      t.string :error_code
      t.datetime :expires_at
      t.string :enqueued_job_id
      t.datetime :enqueued_at
      t.uuid :retry_key, null: false, default: -> { "gen_random_uuid()" }
      t.timestamps
    end
    add_index :draft_cover_requests, :course_id, unique: true, where: "status IN ('queued', 'running', 'recovering')", name: "one_pending_draft_cover"
    add_check_constraint :draft_cover_requests, "status IN ('queued', 'running', 'recovering', 'completed', 'failed', 'cancelled', 'uncertain')", name: "draft_cover_requests_valid_status"
  end
end
