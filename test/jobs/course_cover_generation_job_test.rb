require "test_helper"
require_relative "../support/fake_course_generator"

class CourseCoverGenerationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @ai = Rails.configuration.x.local_ai
    @authoring = Rails.configuration.x.local_authoring
    @old = [ @ai.enabled, @ai.generator, @authoring.enabled ]
    @ai.enabled = @authoring.enabled = true
    @ai.generator = FakeCourseGenerator.new
    @adapter = @ai.cover_generator
    @generation = CourseGeneration.submit!(topic: "Statistics", language: "en", lesson_count: 3, request_key: SecureRandom.uuid)
    CourseGenerationJob.perform_now(@generation, 1)
    @cover = @generation.course.reload.cover_generation
  end

  teardown { @ai.enabled, @ai.generator, @authoring.enabled = @old }

  test "completed lessons schedule one cover and duplicate delivery does not regenerate it" do
    assert @generation.reload.completed?
    assert @cover.queued?
    assert_enqueued_with job: CourseCoverGenerationJob, args: [ @cover, 1 ]
    2.times { CourseCoverGenerationJob.perform_now(@cover, 1) }
    assert @cover.reload.completed?
    assert_equal [ @cover.course_id ], @adapter.calls
    assert_equal File.binread(Rails.root.join("db/seeds/images/commute-times.png")), @cover.course.reload.cover.download
    assert @cover.course.draft?
  end

  test "failure and retry preserve the completed course and its lessons" do
    lesson_ids = @generation.course.lessons.pluck(:id)
    @adapter.error = "usage_limit"
    CourseCoverGenerationJob.perform_now(@cover, 1)
    assert @cover.reload.failed?
    assert_equal "usage_limit", @cover.error_code
    assert @generation.reload.completed?
    assert @cover.retry!(1)
    assert_not @cover.retry!(1)
    @adapter.error = nil
    CourseCoverGenerationJob.perform_now(@cover, 1)
    CourseCoverGenerationJob.perform_now(@cover, 2)
    assert @cover.reload.completed?
    assert_equal lesson_ids, @generation.course.lessons.pluck(:id)
    assert_equal 1, @ai.generator.calls.size
    assert_equal 2, @adapter.calls.size
  end

  test "stale attempts cannot attach a late image or finish a newer attempt" do
    @cover.claim!(1)
    travel 8.minutes do
      @cover.expire_stale!
      assert_equal "timeout", @cover.error_code
      assert @cover.retry!(1)
      @cover.claim!(2)
      upload = ImageUpload.new(Rails.root.join("db/seeds/images/commute-times.png"))
      @cover.complete!(1, upload: upload)
      @cover.fail!(1, "unavailable")
      assert @cover.reload.running?
      assert_not @cover.course.reload.cover.attached?
    end
  end

  test "manual covers are preserved and disabled jobs do not call the model" do
    @ai.enabled = false
    CourseCoverGenerationJob.perform_now(@cover, 1)
    assert_equal "disabled", @cover.reload.error_code
    assert_empty @adapter.calls
    @ai.enabled = true
    @cover.retry!(1)
    blob_id = nil
    @adapter.before_finish = -> { blob_id = CourseCovers::Import.call(course: @cover.course, path: Rails.root.join("db/seeds/images/commute-times.png")).blob.id }
    CourseCoverGenerationJob.perform_now(@cover, 2)
    assert @cover.reload.completed?
    assert_equal 1, ActiveStorage::Attachment.where(record: @cover.course, name: "cover").count
    assert_equal blob_id, @cover.course.reload.cover.blob.id
  end
end
