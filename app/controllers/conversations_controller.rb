class ConversationsController < ApplicationController
  include LearnerContext
  before_action :require_local_ai
  before_action :set_conversation

  def show
    @conversation.expire_stale!
    render_conversation
  end

  def create
    @conversation.expire_stale!
    if params[:selected_text].present? && params[:selection_version].present? &&
        params[:selection_version] != AssistantContext.version(@course) &&
        !@conversation.exchanges.exists?(request_key: params[:request_key])
      return render json: { error: t("conversation.stale_selection") }, status: :conflict
    end
    input = params.permit(:question, :request_key, :selected_text)
    exchange = @conversation.ask!(
      question: input[:question],
      request_key: input[:request_key],
      selected_text: input[:selected_text],
      lesson: @lesson,
      locale: I18n.locale.to_s
    )
    exchange.enqueue if exchange.previously_new_record?
    render_conversation
  rescue Conversation::Busy
    render json: { error: t("conversation.busy") }, status: :conflict
  rescue ActiveRecord::RecordInvalid
    render json: { error: t("conversation.invalid") }, status: :unprocessable_content
  end

  def destroy
    @conversation.history.find(params[:id]).cancel!
    render_conversation
  end

  private

  def require_local_ai
    head :not_found unless LocalAi.available?(request)
  end

  def set_conversation
    scope = params[:lesson_id].present? ? Course.published : Course.all
    @course = scope.find_by!(slug: params[:course_slug])
    raise ActiveRecord::RecordNotFound if @course.draft? && !LocalAuthoring.available?(request)
    mode = AssistantContext.mode(@course)
    if params[:mode].present? && params[:mode] != mode
      return render json: { error: t("conversation.mode_changed"), reload: true, overview_url: overview_url }, status: :conflict
    end
    lesson_id = params[:lesson_id].presence || params[:context_lesson_id].presence
    @lesson = @course.lessons.find(lesson_id) if lesson_id
    @conversation = Conversation.for_course!(course: @course, learner: current_learner_profile,
      browser_key: session[:lesson_chat_key], mode: mode)
  end

  def render_conversation
    exchanges = @conversation.history.to_a
    pending = exchanges.find(&:pending?)
    render json: {
      html: render_to_string(partial: "conversations/transcript", formats: [ :html ], locals: { exchanges: exchanges }),
      activity_html: render_to_string(partial: "conversations/activity", formats: [ :html ], locals: { course: @course }),
      version: AssistantContext.version(@course),
      lesson_ids: @course.lessons.ids,
      overview_url: overview_url,
      busy: pending.present?,
      cancelling: pending&.cancel_requested_at.present?,
      cancel_url: pending && course_conversation_exchange_path(@course, pending, mode: @conversation.mode)
    }
  end

  def overview_url
    return course_path(@course) if @course.published?
    @course.course_generation ? generation_path(@course.course_generation) : draft_path(@course.id)
  end
end
