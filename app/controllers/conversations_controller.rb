class ConversationsController < ApplicationController
  include LearnerContext
  before_action :require_local_ai
  before_action :set_conversation
  rescue_from Drafts::Error, with: :render_editing_error

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
    if params[:context_lesson_id].present? && !@conversation.exchanges.exists?(request_key: input[:request_key])
      @lesson = @course.lessons.find(params[:context_lesson_id])
    end
    exchange = @conversation.ask!(
      question: input[:question],
      request_key: input[:request_key],
      selected_text: input[:selected_text],
      selection_version: params[:selection_version],
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

  def undo
    return unless require_editor
    change = @course.course_changes.where(exchange_id: @conversation.history.select(:id)).find(params[:change_id])
    revision = Integer(params[:expected_revision].to_s, 10)
    Drafts::Access.synchronize(@course) do
      DraftOperation.perform!(request_key: change.undo_key, operation: "user_undo", arguments: { change_id: change.id, revision: revision }) do
        result = change.undo!(expected_revision: revision)
        { change_id: result.id }
      end
    end
    render_conversation
  rescue ArgumentError
    render json: { error: t("editor.errors.revision_conflict") }, status: :conflict
  end

  def cancel_cover
    return unless require_editor
    request = owned_covers.find(params[:cover_id])
    Drafts::Access.synchronize(@course) { request.cancel! }
    render_conversation
  end

  def retry_cover
    return unless require_editor
    request = owned_covers.find(params[:cover_id])
    Drafts::Access.synchronize(@course) do
      DraftOperation.perform!(request_key: request.retry_key, operation: "retry_draft_cover", arguments: { cover_id: request.id }) do
        { cover_request_id: request.retry!.id }
      end
    end
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
    lesson_id = params[:lesson_id].presence
    @lesson = @course.lessons.find(lesson_id) if lesson_id
    @conversation = Conversation.for_course!(course: @course, learner: current_learner_profile,
      browser_key: session[:lesson_chat_key], mode: mode)
  end

  def render_conversation
    @course.reload
    exchanges = @conversation.history.includes(:course_changes, :assistant_activities, :draft_cover_requests).to_a
    pending = exchanges.find(&:pending?)
    exchanges.flat_map(&:assistant_activities).each(&:reconcile!) if @conversation.mode == "editor"
    blocked = editor_blocked(pending)
    @undoable_change = CourseChange.latest_undoable(@course) if @course.draft? && !pending && !blocked
    refresh_keys = exchanges.flat_map(&:assistant_activities).select { |activity| activity.completed? && activity.tool == "refresh_course_view" }.map(&:key)
    render json: {
      html: render_to_string(partial: "conversations/transcript", formats: [ :html ], locals: { exchanges: exchanges }),
      activity_html: render_to_string(partial: "conversations/activity", formats: [ :html ], locals: { course: @course }),
      version: AssistantContext.version(@course),
      editor_blocked: blocked.present?,
      editor_hint: blocked ? t("editor.errors.#{blocked}", default: t("editor.errors.invalid_content")) : nil,
      refresh_requested: refresh_keys.any? && DraftOperation.where(request_key: refresh_keys).where("result ->> 'revision' = ?", @course.revision.to_s).exists?,
      lesson_ids: @course.lessons.ids,
      overview_url: overview_url,
      busy: pending.present?,
      cancelling: pending&.cancel_requested_at.present?,
      cancel_url: pending && course_conversation_exchange_path(@course, pending, mode: @conversation.mode)
    }
  end

  def require_editor
    return true if @course.draft? && @conversation.mode == "editor" && LocalAuthoring.available?(request)
    head :not_found
    false
  end

  def owned_covers
    @course.draft_cover_requests.where(exchange_id: @conversation.history.select(:id))
  end

  def editor_blocked(pending)
    return unless @conversation.mode == "editor"
    Drafts::Access.ensure_available!(@course, exchange: pending, allow_plan: true)
    nil
  rescue Drafts::Error => error
    error.code
  end

  def render_editing_error(error)
    message = error.code == "stale_selection" ? t("conversation.stale_selection") : t("editor.errors.#{error.code}", default: t("editor.errors.invalid_content"))
    render json: { error: message }, status: :conflict
  end

  def overview_url
    return course_path(@course) if @course.published?
    @course.course_generation ? generation_path(@course.course_generation) : draft_path(@course.id)
  end
end
