class AddReviewedGenerationSteps < ActiveRecord::Migration[8.1]
  def up
    change_column_null :course_generations, :lesson_count, true
    remove_check_constraint :course_generations, name: "generations_valid_limits"
    add_check_constraint :course_generations, "(lesson_count IS NULL OR lesson_count BETWEEN 1 AND 60) AND attempt > 0", name: "generations_valid_limits"
    remove_check_constraint :course_generations, name: "generations_valid_status"
    add_check_constraint :course_generations, "status IN ('queued', 'running', 'awaiting_approval', 'completed', 'failed', 'cancelled')", name: "generations_valid_status"
    add_column :course_generations, :stage, :string, null: false, default: "planning"
    add_column :course_generations, :step, :integer, null: false, default: 0
    add_column :course_generations, :current_position, :integer
    add_column :course_generations, :plan_approved_at, :datetime
    add_column :course_generations, :activity, :string
    add_column :course_generations, :activity_at, :datetime
    add_check_constraint :course_generations, "stage IN ('planning', 'writing', 'checking') AND step >= 0 AND (current_position IS NULL OR current_position BETWEEN 1 AND 60)", name: "generations_valid_step"
    execute "UPDATE course_generations SET stage = 'checking', plan_approved_at = updated_at WHERE status = 'completed'"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Reviewed plans may exceed the previous six-lesson limit."
  end
end
