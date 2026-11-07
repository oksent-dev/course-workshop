class CourseGenerationJob < ApplicationJob
  queue_as :default

  def perform(generation, attempt, step = 0)
    token = generation.with_lock do
      value = generation.claim!(attempt, step)
      @run = AiRun.start!(generation, "#{attempt}:#{step}", job_id) if value
      value
    end
    return unless token
    raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?

    cancelled = -> { generation.reload.attempt != attempt || generation.step != step || !generation.running? || !LocalGeneration.enabled? }
    if generation.stage == "illustrating"
      upload = LocalGeneration.illustrator.illustrate(generation, cancelled: cancelled, run: @run)
      raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?
      generation.attach_illustration!(attempt, step, upload)
    elsif generation.stage != "checking"
      LocalGeneration.adapter.generate(generation, token: token,
        cancelled: cancelled, run: @run)
    end
    raise LocalAi::Error, "disabled" unless LocalGeneration.enabled?
    next_step = generation.with_lock do
      advanced = generation.advance!(attempt, step)
      @run.finish!(:completed)
      advanced
    end
    self.class.enqueue(generation) if next_step
  rescue LocalAi::Cancelled
    generation.finish!(attempt, status: :cancelled, expected_step: step)
    @run&.finish!(:cancelled)
  rescue LocalAi::Error => error
    fail_or_recover(generation, attempt, step, error.code)
  rescue ImageUpload::InvalidImage
    fail_or_recover(generation, attempt, step, "invalid_image")
  rescue StandardError => error
    Rails.logger.error("Course generation failed: #{error.class}")
    fail_or_recover(generation, attempt, step, "unavailable")
  end

  def self.enqueue(generation)
    generation.dispatch_job!(self) { [ generation.attempt, generation.step ] }
  end

  private

  def fail_or_recover(generation, attempt, step, code)
    if @run&.submitted_at?
      @run.defer_recovery!
    else
      generation.finish!(attempt, status: :failed, error_code: code, expected_step: step)
      @run&.finish!(:failed, error_code: code)
    end
  end
end
