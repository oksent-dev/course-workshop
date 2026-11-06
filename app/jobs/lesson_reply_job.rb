class LessonReplyJob < ApplicationJob
  queue_as :default

  def perform(exchange)
    exchange.with_lock do
      return unless exchange.queued?
      exchange.update!(status: :running)
    end

    raise LocalAi::Error, "disabled" unless LocalAi.enabled?

    answer = LocalAi.adapter.reply(
      exchange,
      on_thread: ->(id) { exchange.conversation.update!(runtime_thread_id: id) },
      cancelled: -> { exchange.reload.cancel_requested_at.present? || !exchange.running? }
    )
    finish(exchange, :completed, answer: answer)
  rescue LocalAi::Cancelled
    finish(exchange, :cancelled)
  rescue LocalAi::Error => error
    finish(exchange, :failed, error_code: error.code)
  rescue StandardError => error
    Rails.logger.error("Lesson reply failed: #{error.class}")
    finish(exchange, :failed, error_code: "unavailable")
  end

  private

  def finish(exchange, status, **attributes)
    exchange.with_lock do
      return unless exchange.pending?
      if exchange.cancel_requested_at?
        exchange.update!(status: :cancelled)
      else
        exchange.update!(status: status, **attributes)
      end
    end
  end
end
