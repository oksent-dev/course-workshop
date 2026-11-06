class AddCoverGenerationsAndCategoryIdentity < ActiveRecord::Migration[8.1]
  def change
    add_index :categories, "LOWER(name)", unique: true, name: "index_categories_on_normalized_name"

    create_table :course_cover_generations do |t|
      t.references :course, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: "queued"
      t.integer :attempt, null: false, default: 1
      t.string :error_code
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_check_constraint :course_cover_generations, "status IN ('queued', 'running', 'completed', 'failed')", name: "covers_valid_status"
    add_check_constraint :course_cover_generations, "attempt > 0", name: "covers_positive_attempt"
  end
end
