class CoursesController < ApplicationController
  include LearnerContext

  def show
    @course = Course.find_by!(slug: params[:slug])
    @lessons = @course.lessons.outline.to_a
    @progress = CourseProgress.for_lessons(current_learner_profile, @lessons)
  end
end
