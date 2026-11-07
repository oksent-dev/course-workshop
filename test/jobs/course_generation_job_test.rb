require "test_helper"
require_relative "../support/fake_course_generator"

class CourseGenerationJobTest < ActiveSupport::TestCase
  include GenerationTestHelpers

  setup do
    @ai = Rails.configuration.x.local_ai
    @authoring = Rails.configuration.x.local_authoring
    @old = [ @ai.enabled, @ai.generator, @authoring.enabled ]
    @ai.enabled = @authoring.enabled = true
    @ai.generator = @generator = FakeCourseGenerator.new
    @generation = CourseGeneration.submit!(topic: "Active Record", language: "en", request_key: SecureRandom.uuid)
  end

  teardown { @ai.enabled, @ai.generator, @authoring.enabled = @old }

  test "the model selects eighteen lessons and no material is written before approval" do
    @generator.lesson_count = 18
    2.times { CourseGenerationJob.perform_now(@generation, 1) }
    assert @generation.reload.awaiting_approval?
    assert_equal 18, @generation.lesson_count
    assert_empty @generation.course.lessons
    assert_equal 1, @generator.calls.size
    assert_nil @generation.token_digest
    assert_not @generation.approve_plan!(1, 0)
    approve_and_finish(@generation)
    assert @generation.reload.completed?
    assert_equal 18, @generation.course.lessons.count
    assert_equal 19, @generator.calls.size
    assert_not @generation.approve_plan!(1, @generation.course.revision)
    CourseGenerationJob.perform_now(@generation, 1, 1)
    assert_equal 19, @generator.calls.size
    assert @generation.course.draft?
    Drafts::Editor.publish(course_id: @generation.course_id, expected_revision: @generation.course.reload.revision)
    assert @generation.course.reload.published?
  end

  test "failure after saving a lesson resumes the missing steps without changing saved IDs" do
    CourseGenerationJob.perform_now(@generation, 1)
    @generator.fail_after = 1
    approve_and_finish(@generation)
    assert @generation.reload.failed?
    first = @generation.course.lessons.first
    assert_equal "unavailable", @generation.error_code
    assert @generation.retry!(1)
    assert_equal 2, @generation.current_position
    assert_not @generation.retry!(1)
    @generator.fail_after = nil
    CourseGenerationJob.perform_now(@generation, 1, 1)
    CourseGenerationJob.enqueue(@generation)
    perform_course_steps
    assert @generation.reload.completed?
    assert_equal first.id, @generation.course.lessons.first.id
    assert_equal 4, @generator.calls.size
  end

  test "cancellation revokes tokens and late activity or completion cannot change the result" do
    @generator.before_finish = ->(generation, server) do
      generation.cancel!(1)
      response = JSON.parse(server.handle_json(JSON.generate(jsonrpc: "2.0", id: 2, method: "tools/call",
        params: { name: "read_generation", arguments: {} })))
      assert_equal "inactive_generation", response.dig("result", "structuredContent", "code")
    end
    CourseGenerationJob.perform_now(@generation, 1)
    assert @generation.reload.cancelled?
    assert_nil @generation.token_digest
    assert @generation.retry!(1)
    assert @generation.awaiting_approval?
    assert_empty @generation.course.lessons
  end

  test "a missing plan is a retryable incomplete result" do
    @generator.define_singleton_method(:generate) { |*args, **options| nil }
    CourseGenerationJob.perform_now(@generation, 1)
    assert_equal "incomplete", @generation.reload.error_code
    assert @generation.failed?
  end

  test "disabled and cancelled queued jobs do not call the model" do
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

  test "every step gets a fresh deadline and old jobs cannot finish a newer step" do
    token = @generation.claim!(1, 0)
    travel 8.minutes do
      @generation.expire_stale!
      assert_equal "timeout", @generation.reload.error_code
      assert @generation.retry!(1)
      @generation.claim!(2, 0)
      assert_raises(Drafts::Error) { @generation.authorize!(token) }
      @generation.finish!(1, status: :completed, expected_step: 0)
      assert @generation.running?
    end
  end

  test "waiting for plan approval does not expire and retries cannot bypass approval" do
    CourseGenerationJob.perform_now(@generation, 1)
    travel 2.days do
      @generation.expire_stale!
      assert @generation.reload.awaiting_approval?
      CourseGenerationJob.perform_now(@generation, 1, 0)
      assert_empty @generation.course.lessons
      assert_equal 1, @generator.calls.size
    end
  end

  test "a failed illustration resumes only the image step and attaches one validated image" do
    @generator.illustrate_position = 1
    illustrator = @ai.illustrator
    illustrator.error = "usage_limit"
    CourseGenerationJob.perform_now(@generation, 1)
    approve_and_finish(@generation)
    assert_equal "illustrating", @generation.reload.stage
    assert_equal "usage_limit", @generation.error_code
    assert @generation.failed?
    lesson = @generation.course.lessons.first
    saved_body = lesson.body
    assert_equal 2, @generator.calls.size
    @generation.retry!(1)
    illustrator.error = nil
    CourseGenerationJob.enqueue(@generation)
    perform_course_steps
    assert @generation.reload.completed?
    assert_equal 4, @generator.calls.size
    assert_equal 1, lesson.reload.lesson_images.count
    assert lesson.lesson_images.first.file.attached?
    assert lesson.body.start_with?(saved_body)
    assert_equal 1, lesson.body.scan("image:generated-illustration").size
    assert_nil @generation.illustration_prompt
    assert_equal 2, illustrator.calls.size
  end

  test "a previous step cannot finish or fail the next step within the same attempt" do
    CourseGenerationJob.perform_now(@generation, 1)
    @generation.reload.approve_plan!(1, @generation.course.reload.revision)
    token = @generation.claim!(1, 1)
    @generator.generate(@generation, token: token, cancelled: -> { false })
    assert @generation.advance!(1, 1)
    assert_equal 2, @generation.step
    @generation.claim!(1, 2)
    assert_not @generation.advance!(1, 1)
    @generation.finish!(1, status: :failed, expected_step: 1)
    assert @generation.reload.running?
    assert_equal 2, @generation.current_position
    assert_raises(Drafts::Error) { @generation.record_activity!(token, "saving") }
  end

  test "an illustration returned after cancellation cannot attach itself" do
    @generator.illustrate_position = 1
    @ai.illustrator.before_finish = -> { @generation.reload.cancel!(1) }
    CourseGenerationJob.perform_now(@generation, 1)
    approve_and_finish(@generation)
    assert @generation.reload.cancelled?
    assert_empty @generation.course.lessons.first.lesson_images
    assert_equal 1, @generation.course.lessons.count
    assert_nil @generation.course.cover_generation
  end
end
