class AiRun < ApplicationRecord
  include AiConfigured
  belongs_to :subject, polymorphic: true
  enum :status, %w[running recovering completed failed cancelled uncertain].index_with(&:itself)
  scope :active, -> { where(status: %w[running recovering]) }

  def self.start!(subject, operation_key, job_id)
    create!(subject: subject, operation_key: operation_key, job_id: job_id, lease_until: 8.minutes.from_now, ai_configuration: subject.ai_configuration)
  end

  def record!(**attributes)
    with_lock do
      raise LocalAi::Cancelled unless running?
      update!(attributes)
    end
  end

  def submitted!
    record!(submitted_at: Time.current)
  end

  def defer_recovery!
    with_lock do
      return unless running?
      update!(status: :recovering, lease_until: Time.current)
    end
    AiRecoveryJob.perform_later(self)
  end

  def finish!(state, **attributes)
    with_lock { update!(status: state, **attributes) if running? || recovering? }
  end

  def recoverable_now?
    return false unless running? || recovering?
    return true if lease_until <= Time.current
    return false if recovering?
    return false unless ApplicationJob.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)

    SolidQueue::Job.find_by(active_job_id: job_id)&.failed? || false
  end

  def claim_recovery!
    with_lock do
      return false unless recoverable_now?
      update!(status: :recovering, lease_until: 1.minute.from_now, recovery_attempts: recovery_attempts + 1)
      true
    end
  end
end
