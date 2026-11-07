class AiRecoverySweepJob < ApplicationJob
  queue_as :default

  def perform
    return unless LocalAi.enabled?

    Exchange.pending.find_each(&:recover_later!)
    if LocalGeneration.enabled?
      CourseGeneration.queued.find_each { |generation| CourseGenerationJob.enqueue(generation) }
      CourseCoverGeneration.queued.find_each(&:enqueue)
      DraftCoverRequest.queued.find_each(&:enqueue)
      CourseGeneration.running.find_each(&:expire_stale!)
      CourseCoverGeneration.running.find_each(&:expire_stale!)
    end
    AiRun.active.find_each do |run|
      AiRecoveryJob.perform_later(run) if run.recoverable_now?
    end
  end
end
