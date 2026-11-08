class AddCourseGenerationMetadata < ActiveRecord::Migration[8.1]
  def up
    add_column :courses, :generated_at, :datetime
    add_column :courses, :generation_reasoning_effort, :string

    execute <<~SQL
      UPDATE courses
      SET generation_reasoning_effort = NULLIF(course_generations.ai_configuration ->> 'reasoning_effort', ''),
          generated_at = CASE WHEN course_generations.status = 'completed' THEN
            COALESCE(
              (SELECT created_at FROM course_cover_generations WHERE course_id = courses.id),
              CASE WHEN NOT EXISTS (SELECT 1 FROM course_changes WHERE course_id = courses.id)
                THEN course_generations.updated_at END
            ) END
      FROM course_generations
      WHERE course_generations.course_id = courses.id
    SQL
  end

  def down
    remove_column :courses, :generation_reasoning_effort
    remove_column :courses, :generated_at
  end
end
