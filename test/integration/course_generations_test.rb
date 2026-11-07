require "test_helper"
require_relative "../support/fake_course_generator"

class CourseGenerationsTest < ActionDispatch::IntegrationTest
  include GenerationTestHelpers

  setup do
    host! "localhost"
    @local = { "REMOTE_ADDR" => "127.0.0.1" }
    @ai = Rails.configuration.x.local_ai
    @authoring = Rails.configuration.x.local_authoring
    @old = [ @ai.enabled, @ai.generator, @authoring.enabled ]
    @ai.enabled = @authoring.enabled = true
    @ai.generator = FakeCourseGenerator.new
    @input = { topic: "Active Record", language: "en", request_key: SecureRandom.uuid }
  end

  teardown { @ai.enabled, @ai.generator, @authoring.enabled = @old }

  test "a form submission creates one draft and job even after repeated delivery" do
    get new_generation_path(locale: :pl), headers: @local
    assert_select "label", text: "Czego chcesz się nauczyć?"
    assert_enqueued_jobs 1 do
      2.times { submit }
    end
    assert_equal 1, CourseGeneration.count
    generation = CourseGeneration.last
    assert_redirected_to generation_path(generation, locale: :en)
    assert generation.course.draft?
    assert_no_enqueued_jobs { submit(topic: "A different topic") }
    assert_response :unprocessable_content
    assert_equal "Active Record", generation.reload.topic
  end

  test "invalid forms roll back the draft and category" do
    [ { topic: " " }, { topic: "x" * 2001 }, { language: "fr" }, { request_key: "invalid" } ].each do |change|
      assert_no_difference [ "Course.count", "Category.count", "CourseGeneration.count" ] do
        assert_no_enqueued_jobs { submit(**change) }
      end
      assert_response :unprocessable_content
    end
    post generations_path(locale: :en), params: { course_generation: { topic: "Something" } }, headers: @local
    assert_response :unprocessable_content
  end

  test "progress survives reload and approval is blocked until the job completes" do
    submit
    generation = CourseGeneration.last
    patch draft_path(generation.course_id, locale: :en), params: { revision: 0 }, headers: @local
    assert_response :unprocessable_content
    assert generation.course.reload.draft?
    perform_enqueued_jobs
    assert generation.reload.awaiting_approval?
    assert_empty generation.course.lessons
    get generation_path(generation, locale: :pl, format: :json), headers: @local
    assert_equal false, response.parsed_body["busy"]
    assert_includes response.parsed_body["html"], "Przejrzyj plan kursu"
    assert_enqueued_jobs 1 do
      2.times do
        post approve_plan_generation_path(generation, locale: :pl), params: { attempt: 1, revision: generation.course.reload.revision }, headers: @local
      end
    end
    perform_course_steps
    get generation_path(generation, locale: :pl, format: :json), headers: @local
    assert_equal true, response.parsed_body["busy"]
    assert_includes response.parsed_body["html"], "Oczekiwanie na utworzenie okładki"
    before_cover = response.parsed_body["version"]
    perform_enqueued_jobs
    get generation_path(generation, locale: :pl, format: :json), headers: @local
    assert_equal false, response.parsed_body["busy"]
    assert_not_equal before_cover, response.parsed_body["version"]
    assert_includes response.parsed_body["html"], "Okładka zapisana"
    assert_includes response.parsed_body["html"], "Zapisano 3 z 3 lekcji"
    assert_no_match(/token_digest|COURSE_GENERATION_TOKEN/, response.body)
    assert_equal "private, no-store", response.headers["Cache-Control"]
    get localized_root_path(locale: :en), headers: @local
    assert_select "a", text: "Active Record essentials", count: 0
  end

  test "cancel and retry are bound to an attempt and retry enqueues only once" do
    submit
    generation = CourseGeneration.last
    post cancel_generation_path(generation, locale: :en), params: { attempt: 1 }, headers: @local
    assert generation.reload.cancelled?
    assert_enqueued_jobs 1 do
      2.times { post retry_generation_path(generation, locale: :en), params: { attempt: 1 }, headers: @local }
    end
    assert_equal 2, generation.reload.attempt
    post cancel_generation_path(generation, locale: :en), params: { attempt: 1 }, headers: @local
    assert generation.reload.queued?
    perform_enqueued_jobs
    assert generation.reload.awaiting_approval?
  end

  test "a failed cover can be retried separately exactly once through local endpoints" do
    submit
    generation = CourseGeneration.last
    perform_enqueued_jobs
    approve_and_finish(generation)
    @ai.cover_generator.error = "usage_limit"
    perform_enqueued_jobs
    cover = generation.course.cover_generation
    assert cover.failed?
    assert generation.reload.completed?
    get generation_path(generation, locale: :en, format: :json), headers: @local
    assert_equal false, response.parsed_body["busy"]
    assert_includes response.parsed_body["html"], "Retry cover"
    assert_no_enqueued_jobs do
      post retry_cover_generation_path(generation, locale: :en), params: { attempt: 1 }, headers: { "REMOTE_ADDR" => "203.0.113.1" }
    end
    assert_response :not_found
    @ai.enabled = false
    assert_no_enqueued_jobs { post retry_cover_generation_path(generation, locale: :en), params: { attempt: 1 }, headers: @local }
    assert_response :not_found
    @ai.enabled = true
    assert_enqueued_jobs 1 do
      2.times { post retry_cover_generation_path(generation, locale: :pl), params: { attempt: 1 }, headers: @local }
    end
    @ai.cover_generator.error = nil
    perform_enqueued_jobs
    assert cover.reload.completed?
    assert_equal 4, @ai.generator.calls.size
  end

  test "disabled, remote and production requests cannot enqueue or inspect generation" do
    submit
    generation = CourseGeneration.last
    @authoring.enabled = false
    get new_generation_path(locale: :en), headers: @local
    assert_response :not_found
    assert_no_enqueued_jobs { submit }
    assert_response :not_found
    @authoring.enabled = true
    @ai.enabled = false
    get generation_path(generation, locale: :en), headers: @local
    assert_response :not_found
    @ai.enabled = true
    get generation_path(generation, locale: :en), headers: { "REMOTE_ADDR" => "203.0.113.1" }
    assert_response :not_found
    previous_env = Rails.env
    Rails.env = "production"
    assert_no_enqueued_jobs { submit }
    assert_response :not_found
  ensure
    Rails.env = previous_env if previous_env
  end

  test "a stale running attempt becomes retryable on refresh and its partial draft is retained" do
    submit
    generation = CourseGeneration.last
    generation.claim!(1)
    generation.update!(expires_at: 1.minute.ago)
    get generation_path(generation, locale: :en, format: :json), headers: @local
    assert generation.reload.failed?
    assert_equal "timeout", generation.error_code
    assert_includes response.parsed_body["html"], "Resume generation"
    assert generation.course.draft?
  end

  test "plan approval rejects remote requests and stale revisions" do
    submit
    perform_enqueued_jobs
    generation = CourseGeneration.last
    args = { attempt: generation.attempt, revision: generation.course.revision }
    assert_no_enqueued_jobs do
      post approve_plan_generation_path(generation, locale: :en), params: args, headers: { "REMOTE_ADDR" => "203.0.113.1" }
    end
    assert_response :not_found
    assert_no_enqueued_jobs do
      post approve_plan_generation_path(generation, locale: :en), params: args.merge(revision: -1), headers: @local
    end
    assert generation.reload.awaiting_approval?
    assert_empty generation.course.lessons
  end

  test "generated cards open the overview and its approval keeps the existing revision boundary" do
    submit
    generation = CourseGeneration.last
    course = generation.course
    get generation_path(generation, locale: :en), headers: @local
    assert_select "#course-approve", count: 0
    perform_enqueued_jobs
    approve_and_finish(generation)
    cover = course.cover_generation
    CourseCoverGenerationJob.perform_now(cover, cover.attempt)

    get drafts_path(locale: :en), headers: @local
    assert_select "[data-course-card] a[href=?]", generation_path(generation, locale: :en), count: 2
    assert_select "[data-course-card] a[href=?]", draft_path(course.id, locale: :en), count: 0
    @ai.enabled = false
    get drafts_path(locale: :en), headers: @local
    assert_select "[data-course-card] a[href=?]", draft_path(course.id, locale: :en), count: 2
    @ai.enabled = true
    get generation_path(generation, locale: :en), headers: @local
    assert_select "[data-draft-actions] a.btn-outline[href=?]", draft_path(course.id, locale: :en)
    assert_select "[data-draft-actions] form[action=?] #course-approve:not([disabled])", draft_path(course.id, locale: :en)
    revision = course.reload.revision
    assert_select "input[name=revision][value=?]", revision.to_s

    Drafts::Editor.update_course(course_id: course.id, expected_revision: revision, title: course.title,
      description: "Updated course scope.", language: course.language, category_id: course.category_id)
    patch draft_path(course.id, locale: :en), params: { revision: revision }, headers: @local
    assert_response :unprocessable_content
    assert_select "[role=alert]", /draft has changed/
    assert course.reload.draft?
    get generation_path(generation, locale: :en), headers: @local
    assert_select "input[name=revision][value=?]", course.revision.to_s
    patch draft_path(course.id, locale: :en), params: { revision: course.revision }, headers: @local
    assert_redirected_to course_path(course, locale: :en)
    get generation_path(generation, locale: :en), headers: @local
    assert_select "#course-approve", count: 0
    assert_select "a[href=?]", course_path(course, locale: :en), text: "Open course"
    course.lessons.each do |lesson|
      assert_select "a[href=?]", course_lesson_path(course, lesson, locale: :en)
    end
  end

  private

  def submit(**changes)
    post generations_path(locale: :en), params: { course_generation: @input.merge(changes) }, headers: @local
  end
end
