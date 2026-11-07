module DurableDispatch
  extend ActiveSupport::Concern

  included do
    has_many :ai_runs, as: :subject, dependent: :destroy
  end

  def dispatch_job!(job_class, *arguments)
    with_lock do
      return unless queued?
      return if queued_job_exists?

      arguments = yield if block_given?
      job = job_class.perform_later(self, *arguments)
      update!(enqueued_job_id: job.job_id, enqueued_at: Time.current) if job
    end
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError => error
    Rails.logger.error("AI job enqueue failed: #{error.class}")
    false
  end

  private

  def queued_job_exists?
    return false unless enqueued_job_id?
    if ApplicationJob.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
      job = SolidQueue::Job.find_by(active_job_id: enqueued_job_id)
      job && !job.finished? && !job.failed?
    else
      enqueued_at && enqueued_at > 1.minute.ago
    end
  end
end
