class AiRecovery
  MAX_ATTEMPTS = 3

  def initialize(run, history: Codex::History.new)
    @run, @subject, @history = run, run.subject, history
  end

  def call
    return finish_run(:cancelled) unless current_request?

    # Revoke stale generation tools before inspecting committed results.
    if @subject.is_a?(CourseGeneration)
      @subject.with_lock do
        @subject.update!(token_digest: nil, activity: "recovering", activity_at: Time.current) if current_request?
      end
    end
    return if recover_saved_generation

    unless @run.submitted_at?
      return fail_request("interrupted", :failed)
    end

    turn = @history.turn_for(@run)
    if turn && turn["status"] == "completed"
      @run.update!(turn_id: turn.fetch("id"))
      recover_completed_turn(turn)
    elsif turn && %w[failed interrupted].include?(turn["status"])
      fail_request("interrupted", :failed)
    else
      retry_or_uncertain
    end
  rescue LocalAi::Error, ImageUpload::InvalidImage, KeyError => error
    Rails.logger.warn("AI history recovery incomplete: #{error.class}")
    retry_or_uncertain
  end

  private

  def current_request?
    @subject.reload
    case @subject
    when Exchange
      @subject.pending? && !@subject.cancel_requested_at?
    when CourseGeneration
      @subject.running? && @run.operation_key == "#{@subject.attempt}:#{@subject.step}"
    when CourseCoverGeneration
      @subject.running? && @run.operation_key == @subject.attempt.to_s
    else
      false
    end
  end

  def recover_saved_generation
    case @subject
    when CourseGeneration
      saved = case @subject.stage
      when "planning" then @subject.plan.any?
      when "writing" then @subject.course.lessons.exists?(position: @subject.current_position)
      when "illustrating" then @subject.illustration_prompt.blank?
      when "checking" then true
      end
      if saved
        advance_generation
        true
      end
    when CourseCoverGeneration
      if @subject.course.cover.attached?
        @subject.with_lock do
          return false unless current_request?
          @subject.update!(expires_at: 1.minute.from_now)
          @subject.complete!(@subject.attempt, upload: nil)
          finish_run(:completed)
        end
        true
      end
    end
  end

  def recover_completed_turn(turn)
    case @subject
    when Exchange
      answer, ids = Codex::History.answer(turn)
      raise LocalAi::Error, "empty_response" if answer.blank?
      @subject.with_lock do
        return finish_run(:cancelled) unless current_request?
        @subject.finish!(:completed, answer: answer, error_code: nil)
        @run.update!(item_ids: ids)
        finish_run(:completed)
      end
    when CourseCoverGeneration
      upload = Codex::CoverGenerator.new.upload_from_history(turn)
      @subject.with_lock do
        return finish_run(:cancelled) unless current_request?
        @subject.update!(expires_at: 1.minute.from_now)
        @subject.complete!(@subject.attempt, upload: upload)
        finish_run(:completed)
      end
    when CourseGeneration
      if @subject.stage == "illustrating"
        upload = Codex::CoverGenerator.new.upload_from_history(turn)
        @subject.with_lock do
          return finish_run(:cancelled) unless current_request?
          @subject.update!(expires_at: 1.minute.from_now)
          @subject.attach_illustration!(@subject.attempt, @subject.step, upload)
        end
        advance_generation
      else
        fail_request("incomplete", :failed)
      end
    end
  end

  def advance_generation
    next_step = @subject.with_lock do
      return finish_run(:cancelled) unless current_request?
      @subject.update!(expires_at: 1.minute.from_now)
      advance = @subject.advance!(@subject.attempt, @subject.step)
      finish_run(:completed)
      advance
    end
    CourseGenerationJob.enqueue(@subject) if next_step
  end

  def retry_or_uncertain
    if @run.recovery_attempts >= MAX_ATTEMPTS
      fail_request("uncertain", :uncertain)
    else
      if @subject.is_a?(Exchange)
        @subject.with_lock do
          return finish_run(:cancelled) unless current_request?
          @subject.update!(status: :recovering)
        end
      end
      @run.update!(lease_until: 1.minute.from_now)
      AiRecoveryJob.set(wait: 1.minute).perform_later(@run)
    end
  end

  def fail_request(code, state)
    @subject.with_lock do
      return finish_run(:cancelled) unless current_request?
      case @subject
      when Exchange
        @subject.finish!(state, error_code: code)
        conversation = @subject.conversation
        conversation.with_lock do
          if conversation.runtime_thread_id == @run.thread_id
            conversation.update!(runtime_thread_id: nil)
          end
        end
      when CourseGeneration
        @subject.finish!(@subject.attempt, status: :failed, error_code: code)
      when CourseCoverGeneration
        @subject.fail!(@subject.attempt, code)
      end
      finish_run(state, error_code: code)
    end
  end

  def finish_run(state, **attributes)
    @run.finish!(state, **attributes)
    if @subject.is_a?(Exchange) && @subject.reload.pending? && @subject.cancel_requested_at?
      @subject.finish!(:cancelled)
    end
  end
end
