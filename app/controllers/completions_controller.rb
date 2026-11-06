class CompletionsController < ApplicationController
  include LearnerContext

  before_action :set_lesson

  def create
    current_learner_profile.progress_for(@lesson).complete!
    redirect_to course_lesson_path(@course, @lesson, anchor: "lesson-completion"), status: :see_other
  end

  def destroy
    current_learner_profile.lesson_progresses.find_by(lesson: @lesson)&.update!(completed_at: nil)
    redirect_to course_lesson_path(@course, @lesson, anchor: "lesson-completion"), status: :see_other
  end

  private

  def set_lesson
    @course = Course.published.find_by!(slug: params[:course_slug])
    @lesson = @course.lessons.find(params[:lesson_id])
  end
end
