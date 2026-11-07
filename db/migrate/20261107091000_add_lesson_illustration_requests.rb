class AddLessonIllustrationRequests < ActiveRecord::Migration[8.1]
  def up
    add_column :course_generations, :illustration_prompt, :text
    add_column :course_generations, :illustration_alt, :string
    remove_check_constraint :course_generations, name: "generations_valid_step"
    add_check_constraint :course_generations, "stage IN ('planning', 'writing', 'illustrating', 'checking') AND step >= 0 AND (current_position IS NULL OR current_position BETWEEN 1 AND 60)", name: "generations_valid_step"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Pending lesson illustrations must retain their request and stage."
  end
end
