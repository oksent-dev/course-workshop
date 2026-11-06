class CourseCoverGenerationJob < ApplicationJob
  queue_as :default

  def perform(generation, attempt)
    return unless generation.claim!(attempt)
    raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?

    upload = unless generation.course.cover.attached?
      LocalGeneration.cover_adapter.generate(generation.course,
        cancelled: -> { generation.reload.attempt != attempt || !generation.running? || generation.expires_at.past? || !LocalGeneration.enabled? })
    end
    raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?
    generation.complete!(attempt, upload: upload)
  rescue LocalAi::Cancelled
    generation.fail!(attempt, "interrupted")
  rescue LocalAi::Error => error
    generation.fail!(attempt, error.code)
  rescue ImageUpload::InvalidImage
    generation.fail!(attempt, "invalid_image")
  rescue StandardError => error
    Rails.logger.error("Course cover generation failed: #{error.class}")
    generation.fail!(attempt, "unavailable")
  end
end
