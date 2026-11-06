class GenerationsController < ApplicationController
  before_action :require_local_generation
  before_action :set_generation, only: [ :show, :cancel, :retry_generation ]
  helper_method :generation_version

  def new
    @generation = CourseGeneration.new(language: I18n.locale, lesson_count: 4, request_key: SecureRandom.uuid)
    @recent = CourseGeneration.includes(:course).order(id: :desc).limit(10)
  end

  def create
    input = params.require(:course_generation).permit(:topic, :language, :lesson_count, :request_key)
    @generation = CourseGeneration.submit!(**input.to_h.symbolize_keys)
    enqueue if @generation.previously_new_record?
    redirect_to generation_path(@generation), status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    @generation = error.record.is_a?(CourseGeneration) ? error.record : CourseGeneration.new(input)
    @recent = CourseGeneration.includes(:course).order(id: :desc).limit(10)
    @error = t("generation.invalid")
    render :new, status: :unprocessable_content
  end

  def show
    @generation.expire_stale!
    @saved_positions = @generation.course.lessons.pluck(:position)
    respond_to do |format|
      format.html
      format.json { render json: { html: render_to_string(partial: "status", formats: [ :html ]), busy: @generation.pending?, version: generation_version } }
    end
  end

  def cancel
    @generation.cancel!(params[:attempt].to_i)
    redirect_to generation_path(@generation), status: :see_other
  end

  def retry_generation
    @generation.expire_stale!
    enqueue if @generation.retry!(params[:attempt].to_i)
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
    [ @generation.updated_at.to_f, @generation.course.updated_at.to_f, @saved_positions ].to_json
  end

  def enqueue
    attempt = @generation.attempt
    unless CourseGenerationJob.perform_later(@generation, attempt)
      @generation.finish!(attempt, status: :failed, error_code: "unavailable")
    end
  rescue ActiveJob::EnqueueError
    @generation.finish!(attempt, status: :failed, error_code: "unavailable")
  end
end
