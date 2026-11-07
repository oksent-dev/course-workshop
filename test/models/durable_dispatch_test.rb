require "test_helper"

class DurableDispatchTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "a queue outage retains the accepted request for later dispatch" do
    conversation = lessons(:pitch).conversations.create!(browser_key: SecureRandom.hex(32))
    exchange = conversation.ask!(question: "Keep this request", request_key: SecureRandom.uuid, locale: "en")
    unavailable_queue = Class.new do
      def self.perform_later(*)
        raise ActiveJob::EnqueueError, "queue unavailable"
      end
    end
    assert_equal false, exchange.dispatch_job!(unavailable_queue)
    assert exchange.reload.queued?
    assert_nil exchange.enqueued_job_id
    assert_enqueued_jobs(1, only: LessonReplyJob) { 2.times { exchange.enqueue } }
    assert exchange.reload.enqueued_job_id?
  end

  test "dispatch reads the current attempt under the record lock" do
    generation = CourseGeneration.submit!(topic: "Music", language: "en", request_key: SecureRandom.uuid)
    stale = CourseGeneration.find(generation.id)
    generation.cancel!(1)
    generation.retry!(1)
    assert_enqueued_with(job: CourseGenerationJob, args: [ generation, 2, 0 ]) do
      CourseGenerationJob.enqueue(stale)
    end
  end
end
