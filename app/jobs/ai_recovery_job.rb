class AiRecoveryJob < ApplicationJob
  queue_as :default
  limits_concurrency key: ->(run) { run }, duration: 2.minutes, on_conflict: :discard

  def perform(run)
    return unless LocalAi.enabled?
    return if !run.subject.is_a?(Exchange) && !LocalGeneration.enabled?
    return unless run.claim_recovery!

    AiRecovery.new(run).call
  end
end
