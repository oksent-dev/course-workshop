require "test_helper"
require_relative "../support/fake_course_generator"

class AiRecoveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    conversation = lessons(:pitch).conversations.create!(browser_key: SecureRandom.hex(32), runtime_thread_id: "thread-1")
    @exchange = conversation.ask!(question: "Explain", request_key: SecureRandom.uuid, locale: "en")
    @exchange.update!(status: :running)
    @run = AiRun.start!(@exchange, "reply", SecureRandom.uuid)
    @run.update!(thread_id: "thread-1", turn_id: "turn-1", submitted_at: Time.current,
      status: :recovering, recovery_attempts: 1)
  end

  test "a completed stored turn restores one answer and deduplicates runtime item IDs" do
    item = { "id" => "message-1", "type" => "agentMessage", "phase" => "final_answer", "text" => "Recovered answer" }
    turn = { "id" => "turn-1", "status" => "completed", "items" => [ item, item ] }
    assert_no_enqueued_jobs { 2.times { recover(turn) } }
    assert @exchange.reload.completed?
    assert_equal "Recovered answer", @exchange.answer
    assert_equal [ "message-1" ], @run.reload.item_ids
    assert_equal 1, @exchange.conversation.exchanges.count
  end

  test "an unknown outcome is bounded and never resubmits to the model" do
    assert_enqueued_with(job: AiRecoveryJob) { recover(nil) }
    assert @exchange.reload.recovering?
    @run.update!(recovery_attempts: 3)
    assert_no_enqueued_jobs { recover(nil) }
    assert @exchange.reload.uncertain?
    assert_nil @exchange.conversation.reload.runtime_thread_id
    assert_equal "Explain", @exchange.question
    assert_nil @exchange.answer
  end

  test "unavailable history preserves the question and becomes uncertain after bounded checks" do
    @run.update!(recovery_attempts: 3)
    history = Object.new
    history.define_singleton_method(:turn_for) { |_| raise LocalAi::Error, "unavailable" }
    AiRecovery.new(@run, history: history).call
    assert @exchange.reload.uncertain?
    assert_equal "uncertain", @exchange.error_code
  end

  test "a cancelled request cannot be overwritten by recovery" do
    @exchange.cancel!
    recover({ "id" => "turn-1", "status" => "completed", "items" => [] })
    assert @exchange.reload.cancelled?
    assert_nil @exchange.answer
  end

  test "interruption before submission never invents a runtime answer" do
    @run.update!(submitted_at: nil, thread_id: nil, turn_id: nil)
    assert_no_enqueued_jobs { recover(nil) }
    assert @exchange.reload.failed?
    assert_equal "interrupted", @exchange.error_code
  end

  test "recovery claims cannot overlap while their lease is current" do
    @run.update!(lease_until: 1.second.ago)
    assert @run.claim_recovery!
    assert_not AiRun.find(@run.id).claim_recovery!
  end

  test "a plan saved before a lost response is recovered without writing lessons" do
    generation = CourseGeneration.submit!(topic: "Music", language: "en", request_key: SecureRandom.uuid)
    token = generation.claim!(1, 0)
    FakeCourseGenerator.new.generate(generation, token: token, cancelled: -> { false })
    run = AiRun.start!(generation, "1:0", SecureRandom.uuid)
    run.update!(submitted_at: Time.current, status: :recovering)
    history = Object.new
    history.define_singleton_method(:turn_for) { |_| raise "Committed work needs no model request" }
    AiRecovery.new(run, history: history).call
    assert generation.reload.awaiting_approval?
    assert_nil generation.token_digest
    assert_equal 3, generation.plan.size
    assert_empty generation.course.lessons
    assert run.reload.completed?
  end

  test "recovery cannot finish a newer generation attempt" do
    generation = CourseGeneration.submit!(topic: "Music", language: "en", request_key: SecureRandom.uuid)
    generation.claim!(1, 0)
    run = AiRun.start!(generation, "1:0", SecureRandom.uuid)
    generation.cancel!(1)
    generation.retry!(1)
    generation.claim!(2, 0)
    AiRecovery.new(run).call
    assert generation.reload.running?
    assert_equal 2, generation.attempt
    assert run.reload.cancelled?
  end

  test "a committed lesson advances once without rewriting its content" do
    generation = CourseGeneration.submit!(topic: "Music", language: "en", request_key: SecureRandom.uuid)
    generator = FakeCourseGenerator.new
    token = generation.claim!(1, 0)
    generator.generate(generation, token: token, cancelled: -> { false })
    generation.advance!(1, 0)
    generation.approve_plan!(1, generation.course.reload.revision)
    step = generation.step
    token = generation.claim!(1, step)
    generator.generate(generation, token: token, cancelled: -> { false })
    lesson = generation.course.lessons.first!
    original_body = lesson.body
    run = AiRun.start!(generation, "1:#{step}", SecureRandom.uuid)
    run.update!(submitted_at: Time.current, status: :recovering)
    history = Object.new
    history.define_singleton_method(:turn_for) { |_| raise "Already saved" }

    assert_enqueued_jobs(1, only: CourseGenerationJob) do
      2.times { AiRecovery.new(run, history: history).call }
    end
    assert generation.reload.queued?
    assert_equal 2, generation.current_position
    assert_equal 1, generation.course.lessons.count
    assert_equal original_body, lesson.reload.body
    assert run.reload.completed?
  end

  test "a completed cover turn restores validated bytes without generating another image" do
    generation = CourseGeneration.submit!(topic: "Music", language: "en", request_key: SecureRandom.uuid)
    cover = generation.course.create_cover_generation!(expires_at: 7.minutes.from_now)
    cover.claim!(1)
    run = AiRun.start!(cover, "1", SecureRandom.uuid)
    run.update!(submitted_at: Time.current, thread_id: "image-thread", turn_id: "image-turn", status: :recovering)
    turn = { "id" => "image-turn", "status" => "completed", "items" => [
      { "id" => "image-result", "type" => "imageGeneration", "status" => "completed",
        "result" => Base64.strict_encode64(File.binread(Rails.root.join("db/seeds/images/commute-times.png"))) }
    ] }
    history = Object.new
    history.define_singleton_method(:turn_for) { |_| turn }
    assert_no_enqueued_jobs { 2.times { AiRecovery.new(run, history: history).call } }
    assert cover.reload.completed?
    assert run.reload.completed?
    assert generation.course.reload.cover.attached?
    assert_equal "image/png", generation.course.cover.content_type
    assert_empty Rails.configuration.x.local_ai.cover_generator.calls
  end

  private

  def recover(turn)
    history = Object.new
    history.define_singleton_method(:turn_for) { |_| turn }
    AiRecovery.new(@run, history: history).call
  end
end
