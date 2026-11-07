class CourseGenerationJob < ApplicationJob
  queue_as :default

  def perform(generation, attempt, step = 0)
    token = generation.claim!(attempt, step)
    return unless token
    raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?

    cancelled = -> { generation.reload.attempt != attempt || generation.step != step || !generation.running? || !LocalGeneration.enabled? }
    if generation.stage == "illustrating"
      upload = LocalGeneration.illustrator.illustrate(generation, cancelled: cancelled)
      raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?
      generation.attach_illustration!(attempt, step, upload)
    elsif generation.stage != "checking"
      LocalGeneration.adapter.generate(generation, token: token,
        cancelled: cancelled)
    end
    raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?
    self.class.enqueue(generation) if generation.advance!(attempt, step)
  rescue LocalAi::Cancelled
    generation.finish!(attempt, status: :cancelled, expected_step: step)
  rescue LocalAi::Error => error
    generation.finish!(attempt, status: :failed, error_code: error.code, expected_step: step)
  rescue ImageUpload::InvalidImage
    generation.finish!(attempt, status: :failed, error_code: "invalid_image", expected_step: step)
  rescue StandardError => error
    Rails.logger.error("Course generation failed: #{error.class}")
    generation.finish!(attempt, status: :failed, error_code: "unavailable", expected_step: step)
  end

  def self.enqueue(generation)
    return unless generation.queued?
    attempt, step = generation.attempt, generation.step
    unless perform_later(generation, attempt, step)
      generation.finish!(attempt, status: :failed, error_code: "unavailable", expected_step: step)
    end
  rescue ActiveJob::EnqueueError
    generation.finish!(attempt, status: :failed, error_code: "unavailable", expected_step: step)
  end
end
