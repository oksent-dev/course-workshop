class GenerationsController < ApplicationController
  include LearnerContext
  before_action :require_local_generation
  before_action :set_generation, only: [ :show, :cancel, :retry_generation, :retry_cover, :approve_plan ]
  helper_method :generation_version, :generation_busy?
  rescue_from Drafts::Error do |error|
    redirect_to generation_path(@generation), status: :see_other,
      alert: t("editor.errors.#{error.code}", default: t("editor.errors.invalid_content"))
  end

  def new
    @generation = CourseGeneration.new(language: I18n.locale, request_key: SecureRandom.uuid)
    @recent = CourseGeneration.includes(:course).order(id: :desc).limit(10)
  end

  def create
    input = params.require(:course_generation).permit(:topic, :language, :request_key)
    @generation = CourseGeneration.submit!(**input.to_h.symbolize_keys)
    CourseGenerationJob.enqueue(@generation) if @generation.previously_new_record?
    redirect_to generation_path(@generation), status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    @generation = error.record.is_a?(CourseGeneration) ? error.record : CourseGeneration.new(input)
    @recent = CourseGeneration.includes(:course).order(id: :desc).limit(10)
    @error = t("generation.invalid")
    render :new, status: :unprocessable_content
  end

  def show
    @generation.expire_stale!
    @course = @generation.course
    @cover_generation = @generation.course.cover_generation
    @cover_generation&.expire_stale!
    @saved_lessons = @generation.course.lessons.pluck(:position, :id).to_h
    @saved_positions = @saved_lessons.keys
    respond_to do |format|
      format.html
      format.json { render json: { html: render_to_string(partial: "status", formats: [ :html ]), busy: generation_busy?, version: generation_version } }
    end
  end

  def cancel
    @generation.cancel!(params[:attempt].to_i)
    redirect_to generation_path(@generation), status: :see_other
  end

  def retry_generation
    @generation.expire_stale!
    CourseGenerationJob.enqueue(@generation) if @generation.retry!(params[:attempt].to_i)
    redirect_to generation_path(@generation), status: :see_other
  end

  def approve_plan
    if @generation.approve_plan!(params[:attempt].to_i, params[:revision].to_i)
      CourseGenerationJob.enqueue(@generation)
    end
    redirect_to generation_path(@generation), status: :see_other
  end

  def retry_cover
    cover = @generation.course.cover_generation
    cover&.expire_stale!
    cover.enqueue if @generation.completed? && cover&.retry!(params[:attempt].to_i)
    redirect_to generation_path(@generation), status: :see_other
  end

  private

  def require_local_generation
    response.headers["Cache-Control"] = "private, no-store"
    head :not_found unless LocalGeneration.available?(request)
  end

  def set_generation
    @generation = CourseGeneration.find(params[:id])
  end

  def generation_version
    [ @generation.updated_at.to_f, @generation.course.updated_at.to_f, @cover_generation&.updated_at&.to_f, @saved_positions ].to_json
  end

  def generation_busy?
    @generation.pending? || @cover_generation&.pending? || false
  end
end
