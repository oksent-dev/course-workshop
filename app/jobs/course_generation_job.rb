class CourseGenerationJob < ApplicationJob
  queue_as :default

  def perform(generation, attempt)
    token = generation.claim!(attempt)
    return unless token
    raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?

    LocalGeneration.adapter.generate(generation, token: token,
      cancelled: -> { generation.reload.attempt != attempt || !generation.running? || !LocalGeneration.enabled? })
    generation.complete!(attempt)
  rescue LocalAi::Cancelled
    generation.finish!(attempt, status: :cancelled)
  rescue LocalAi::Error => error
    generation.finish!(attempt, status: :failed, error_code: error.code)
  rescue StandardError => error
    Rails.logger.error("Course generation failed: #{error.class}")
    generation.finish!(attempt, status: :failed, error_code: "unavailable")
  end
end
