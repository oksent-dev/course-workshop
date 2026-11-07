class Exchange < ApplicationRecord
  include DurableDispatch
  MAX_SELECTION_LENGTH = 2000

  belongs_to :conversation
  store_accessor :lesson_context, :selected_text

  enum :status, %w[queued running recovering completed failed cancelled uncertain].index_with(&:itself)
  scope :pending, -> { where(status: %w[queued running recovering]) }

  validates :question, presence: true, length: { maximum: 4000 }
  validates :request_key, format: { with: /\A[0-9a-f-]{36}\z/ }, uniqueness: { scope: :conversation_id }
  validates :locale, inclusion: { in: %w[pl en] }
  validates :lesson_context, presence: true
  validates :selected_text, length: { maximum: MAX_SELECTION_LENGTH }, allow_nil: true

  def pending?
    queued? || running? || recovering?
  end

  def enqueue
    dispatch_job!(LessonReplyJob)
  end

  def recover_later!
    if queued?
      enqueue
    elsif (run = ai_runs.active.first)
      AiRecoveryJob.perform_later(run) if run.recoverable_now?
    elsif running? && updated_at < 8.minutes.ago
      finish!(:uncertain, error_code: "uncertain")
    end
  end

  def finish!(state, **attributes)
    with_lock do
      return unless pending?
      if cancel_requested_at?
        update!(status: :cancelled)
      else
        update!(status: state, **attributes)
      end
    end
  end

  def cancel!
    with_lock do
      if queued?
        update!(status: :cancelled)
      elsif recovering?
        update!(status: :cancelled, cancel_requested_at: Time.current)
      elsif running?
        update!(cancel_requested_at: Time.current)
      end
    end
  end
end
