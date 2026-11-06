require "test_helper"
require_relative "../support/fake_course_generator"

class CourseGenerationJobTest < ActiveSupport::TestCase
  setup do
    @ai = Rails.configuration.x.local_ai
    @authoring = Rails.configuration.x.local_authoring
    @old = [ @ai.enabled, @ai.generator, @authoring.enabled ]
    @ai.enabled = @authoring.enabled = true
    @ai.generator = @generator = FakeCourseGenerator.new
    @generation = CourseGeneration.submit!(topic: "Active Record", language: "en", lesson_count: 3, request_key: SecureRandom.uuid)
  end

  teardown { @ai.enabled, @ai.generator, @authoring.enabled = @old }

  test "a completed job leaves a validated draft and duplicate delivery does not run the model" do
    2.times { CourseGenerationJob.perform_now(@generation, 1) }
    assert @generation.reload.completed?
    assert_nil @generation.token_digest
    assert @generation.course.draft?
    assert_equal 3, @generation.course.lessons.count
    assert_equal 1, @generator.calls.size
    Drafts::Editor.publish(course_id: @generation.course_id, expected_revision: @generation.course.reload.revision)
    assert @generation.course.reload.published?
  end

  test "a failure after one lesson resumes the same plan, course and lesson without duplicates" do
    @generator.fail_after = 1
    CourseGenerationJob.perform_now(@generation, 1)
    assert @generation.reload.failed?
    first_id = @generation.course.lessons.first.id
    plan = @generation.plan
    assert_equal "unavailable", @generation.error_code
    assert @generation.retry!(1)
    assert_not @generation.retry!(1)
    @generator.fail_after = nil
    CourseGenerationJob.perform_now(@generation, 1)
    CourseGenerationJob.perform_now(@generation, 2)
    assert @generation.reload.completed?
    assert_equal first_id, @generation.course.lessons.first.id
    assert_equal plan, @generation.plan
    assert_equal 3, @generation.course.lessons.count
    assert_equal 2, @generator.calls.size
  end

  test "cancellation prevents late completion and revokes the writing server immediately" do
    @generator.before_finish = ->(generation, server) do
      generation.cancel!(1)
      response = JSON.parse(server.handle_json(JSON.generate(jsonrpc: "2.0", id: 2, method: "tools/call",
        params: { name: "save_generated_lesson", arguments: { position: 1, body: FakeCourseGenerator::BODY, request_key: SecureRandom.uuid } })))
      assert_equal "inactive_generation", response.dig("result", "structuredContent", "code")
    end
    CourseGenerationJob.perform_now(@generation, 1)
    assert @generation.reload.cancelled?
    assert_nil @generation.token_digest
    assert @generation.course.draft?
  end

  test "model completion without all lessons is a retryable incomplete draft" do
    @generator.define_singleton_method(:generate) { |*args, **options| nil }
    CourseGenerationJob.perform_now(@generation, 1)
    assert_equal "incomplete", @generation.reload.error_code
    assert @generation.failed?
    assert @generation.course.draft?
  end

  test "disabled authoring and cancelled queued jobs do not call the model" do
    @authoring.enabled = false
    CourseGenerationJob.perform_now(@generation, 1)
    assert_equal "disabled", @generation.reload.error_code
    assert_empty @generator.calls
    @generation.retry!(1)
    @generation.cancel!(2)
    CourseGenerationJob.perform_now(@generation, 2)
    assert @generation.reload.cancelled?
    assert_empty @generator.calls
  end

  test "expired attempts are recoverable and late results cannot complete a newer attempt" do
    old_token = @generation.claim!(1)
    travel 13.minutes do
      @generation.expire_stale!
      assert_equal "timeout", @generation.reload.error_code
      assert @generation.retry!(1)
      @generation.claim!(2)
      assert_raises(Drafts::Error) { @generation.authorize!(old_token) }
      @generation.finish!(1, status: :completed)
      assert @generation.running?
      @generation.cancel!(1)
      assert @generation.running?
    end
  end
end
