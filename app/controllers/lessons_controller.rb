class LessonsController < ApplicationController
  def show
    @course = Course.find_by!(slug: params[:course_slug])
    @lesson = @course.lessons.find(params[:id])
    @lessons = @course.lessons.outline.to_a
    index = @lessons.index(@lesson)
    @lesson_number = index + 1
    @previous_lesson = @lessons[index - 1] if index.positive?
    @next_lesson = @lessons[index + 1]
  end
end
