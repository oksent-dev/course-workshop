class PagesController < ApplicationController
  include LearnerContext

  def home
    @categories = Category.joins(:courses).distinct.order(:name).preload(:courses).load
    @progress_by_course = CourseProgress.for_courses(current_learner_profile, @categories.flat_map(&:courses))
  end
end
