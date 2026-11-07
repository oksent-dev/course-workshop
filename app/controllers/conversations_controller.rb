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
    course = Course.published.find_by!(slug: params[:course_slug])
    @lesson = course.lessons.find(params[:lesson_id])
    @conversation = Conversation.for_course!(course: course, learner: current_learner_profile,
      browser_key: session[:lesson_chat_key])
  end

  def render_conversation
    exchanges = @conversation.history.to_a
    pending = exchanges.find(&:pending?)
    render json: {
      html: render_to_string(partial: "conversations/transcript", formats: [ :html ], locals: { exchanges: exchanges }),
      busy: pending.present?,
      cancelling: pending&.cancel_requested_at.present?,
      cancel_url: pending && course_lesson_conversation_exchange_path(
        params[:course_slug], params[:lesson_id], pending
      )
    }
  end
end
