class LessonsController < ApplicationController
  include LearnerContext

  def show
    @course = Course.published.find_by!(slug: params[:course_slug])
    @lesson = @course.lessons.find(params[:id])
    @lessons = @course.lessons.outline.to_a
    unless request.head? || request.headers["X-Sec-Purpose"] == "prefetch" || request.headers["Sec-Purpose"]&.include?("prefetch")
      current_learner_profile.progress_for(@lesson).update!(last_opened_at: Time.current)
    end
    @progress = CourseProgress.for_lessons(current_learner_profile, @lessons)
    index = @lessons.index(@lesson)
    @lesson_number = index + 1
    @previous_lesson = @lessons[index - 1] if index.positive?
    @next_lesson = @lessons[index + 1]
  end
end
