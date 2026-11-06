class PagesController < ApplicationController
  include LearnerContext

  def home
    @categories = Category.joins(:published_courses).distinct.order(:name).preload(:published_courses).load
    @progress_by_course = CourseProgress.for_courses(current_learner_profile, @categories.flat_map(&:published_courses))
  end
end
