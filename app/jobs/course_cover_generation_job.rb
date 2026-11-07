class CourseCoverGenerationJob < ApplicationJob
  queue_as :default

  def perform(generation, attempt)
    claimed = generation.with_lock do
      value = generation.claim!(attempt)
      @run = AiRun.start!(generation, attempt.to_s, job_id) if value
      value
    end
    return unless claimed
    raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?

    upload = unless generation.course.cover.attached?
      LocalGeneration.cover_adapter.generate(generation.course, run: @run,
        cancelled: -> { generation.reload.attempt != attempt || !generation.running? || generation.expires_at.past? || !LocalGeneration.enabled? })
    end
    raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?
    generation.with_lock do
      generation.complete!(attempt, upload: upload)
      @run.finish!(:completed)
    end
  rescue LocalAi::Cancelled
    generation.fail!(attempt, "interrupted")
    @run&.finish!(:cancelled)
  rescue LocalAi::Error => error
    fail_or_recover(generation, attempt, error.code)
  rescue ImageUpload::InvalidImage
    fail_or_recover(generation, attempt, "invalid_image")
  rescue StandardError => error
    Rails.logger.error("Course cover generation failed: #{error.class}")
    fail_or_recover(generation, attempt, "unavailable")
  end

  private

  def fail_or_recover(generation, attempt, code)
    if @run&.submitted_at?
      @run.defer_recovery!
    else
      generation.fail!(attempt, code)
      @run&.finish!(:failed, error_code: code)
    end
  end
end
