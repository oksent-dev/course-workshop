class LessonReplyJob < ApplicationJob
  queue_as :default

  def perform(exchange)
    exchange.with_lock do
      return unless exchange.queued?
      exchange.update!(status: :running)
      @run = AiRun.start!(exchange, "reply", job_id)
    end

    raise LocalAi::Error, "disabled" unless LocalAi.enabled?

    answer = LocalAi.adapter.reply(
      exchange,
      run: @run,
      on_thread: ->(id) { exchange.conversation.update!(runtime_thread_id: id) },
      cancelled: -> { exchange.reload.cancel_requested_at.present? || !exchange.running? || !LocalAi.enabled? }
    )
    finish(exchange, :completed, answer: answer)
  rescue LocalAi::Cancelled
    finish(exchange, :cancelled)
  rescue LocalAi::Error => error
    if @run&.submitted_at? && exchange.reload.running? && !exchange.cancel_requested_at?
      exchange.with_lock { exchange.update!(status: :recovering) if exchange.running? && !exchange.cancel_requested_at? }
      @run.defer_recovery!
    else
      finish(exchange, :failed, error_code: error.code)
    end
  rescue StandardError => error
    Rails.logger.error("Lesson reply failed: #{error.class}")
    if @run&.submitted_at?
      exchange.update!(status: :recovering) if exchange.reload.running?
      @run.defer_recovery!
    else
      finish(exchange, :failed, error_code: "unavailable")
    end
  end

  private

  def finish(exchange, status, **attributes)
    exchange.with_lock do
      return unless exchange.pending?
      exchange.finish!(status, **attributes)
      @run&.finish!(exchange.status, error_code: exchange.error_code)
    end
  end
end
