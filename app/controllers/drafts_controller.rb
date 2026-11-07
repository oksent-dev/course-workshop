class DraftsController < ApplicationController
  include LearnerContext
  before_action :require_local_authoring
  before_action :set_draft, only: [ :show, :update ]

  def index
    @category_counts = Course.draft.group(:category_id).count
    @categories = Category.where(id: @category_counts.keys).order(:name).to_a
    if params[:category].present?
      @selected_category = @categories.find { |category| category.id.to_s == params[:category] }
      raise ActiveRecord::RecordNotFound unless @selected_category
    end
    @drafts = Course.draft.includes(:category, :course_generation).with_attached_cover.order(updated_at: :desc, id: :desc)
    @drafts = @drafts.where(category: @selected_category) if @selected_category
    @drafts = @drafts.to_a
    @lesson_counts = Lesson.where(course_id: @drafts.map(&:id)).group(:course_id).count
  end

  def show
  end

  def update
    Drafts::Editor.publish(course_id: @course.id, expected_revision: Integer(params[:revision].to_s, 10))
    redirect_to course_path(@course), status: :see_other, notice: t("drafts.published")
  rescue Drafts::Error => error
    @error = t("drafts.errors.#{error.code == "revision_conflict" ? "revision_conflict" : "invalid_content"}")
    set_draft
    render :show, status: :unprocessable_content
  rescue ArgumentError
    @error = t("drafts.errors.revision_conflict")
    render :show, status: :unprocessable_content
  end

  private

  def require_local_authoring
    response.headers["Cache-Control"] = "private, no-store"
    head :not_found unless LocalAuthoring.available?(request)
  end

  def set_draft
    @course = Course.draft.find(params[:id])
    @lessons = @course.lessons.outline.to_a
    lesson_id = params[:lesson_id].presence || @lessons.first&.id
    @lesson = @course.lessons.find(lesson_id) if lesson_id
  end
end
