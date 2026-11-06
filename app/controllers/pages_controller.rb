class PagesController < ApplicationController
  include LearnerContext

  def home
    @category_counts = Course.published.group(:category_id).count
    @categories = Category.where(id: @category_counts.keys).order(:name).to_a
    if params[:category].present?
      @selected_category = @categories.find { |category| category.id.to_s == params[:category] }
      raise ActiveRecord::RecordNotFound unless @selected_category
    end
    @courses = Course.published.includes(:category).with_attached_cover.order(:title, :id)
    @courses = @courses.where(category: @selected_category) if @selected_category
    @courses = @courses.to_a
    @progress_by_course = CourseProgress.for_courses(current_learner_profile, @courses)
  end
end
