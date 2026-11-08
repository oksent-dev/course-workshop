class CompletionsController < ApplicationController
  include LearnerContext

  before_action :set_lesson

  def create
    current_learner_profile.progress_for(@lesson).complete!
    render_progress
  end

  def destroy
    current_learner_profile.lesson_progresses.find_by(lesson: @lesson)&.update!(completed_at: nil)
    render_progress
  end

  private

  def render_progress
    respond_to do |format|
      format.turbo_stream do
        @lessons = @course.lessons.outline.to_a
        @progress = CourseProgress.for_lessons(current_learner_profile, @lessons)
        render :update
      end
      format.html do
        redirect_to course_lesson_path(@course, @lesson, anchor: "lesson-completion"), status: :see_other
      end
    end
  end

  def set_lesson
    @course = Course.published.find_by!(slug: params[:course_slug])
    @lesson = @course.lessons.find(params[:lesson_id])
  end
end
