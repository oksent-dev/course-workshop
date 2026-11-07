class DraftCoverJob < ApplicationJob
  queue_as :default

  def perform(request)
    request.with_lock do
      return unless request.queued?
      request.update!(status: :running, expires_at: 7.minutes.from_now)
      @run = AiRun.start!(request, "cover", job_id)
    end
    raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?
    upload = LocalGeneration.cover_adapter.generate(request.course, run: @run,
      brief: { title: request.course.title, description: request.course.description, visual_brief: request.prompt },
      cancelled: -> { !request.reload.running? || request.expires_at.past? || request.cancelled_by_exchange? || !LocalGeneration.enabled? })
    raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?
    request.complete!(upload)
    @run.finish!(request.reload.status, error_code: request.error_code)
  rescue LocalAi::Cancelled
    request.cancel!
    @run&.finish!(:cancelled)
  rescue LocalAi::Error, ImageUpload::InvalidImage, Drafts::Error => error
    fail_or_recover(request, error.respond_to?(:code) ? error.code : "invalid_image")
  rescue StandardError => error
    Rails.logger.error("Draft cover failed: #{error.class}")
    fail_or_recover(request, "unavailable")
  end

  private

  def fail_or_recover(request, code)
    if @run&.submitted_at? && request.reload.pending?
      request.update!(status: :recovering)
      @run.defer_recovery!
    else
      request.fail!(code)
      @run&.finish!(:failed, error_code: code)
    end
  end
end
