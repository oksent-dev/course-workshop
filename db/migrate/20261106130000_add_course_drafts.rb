class AddCourseDrafts < ActiveRecord::Migration[8.1]
  def up
    add_column :courses, :status, :string, null: false, default: "draft"
    add_column :courses, :revision, :integer, null: false, default: 0
    execute "UPDATE courses SET status = 'published'"
    add_check_constraint :courses, "status IN ('draft', 'published')", name: "courses_valid_status"
    add_check_constraint :courses, "revision >= 0", name: "courses_nonnegative_revision"

    create_table :draft_operations do |t|
      t.uuid :request_key, null: false
      t.string :fingerprint, null: false
      t.jsonb :result, null: false, default: {}
      t.timestamps
      t.index :request_key, unique: true
    end
  end

  def down
    drop_table :draft_operations
    remove_check_constraint :courses, name: "courses_valid_status"
    remove_check_constraint :courses, name: "courses_nonnegative_revision"
    remove_column :courses, :revision
    remove_column :courses, :status
  end
end
