require "test_helper"
require_relative "../support/draft_editing"

class DraftCoverJobTest < ActiveSupport::TestCase
  include DraftEditing
  include ActiveJob::TestHelper

  setup do
    @ai, @authoring = Rails.configuration.x.local_ai, Rails.configuration.x.local_authoring
    @enabled = [ @ai.enabled, @authoring.enabled ]
    @ai.enabled = @authoring.enabled = true
    @exchange = start_editor
    @course = @exchange.conversation.course
    @course.cover.attach(ImageUpload.new(bytes: Vips::Image.black(10, 10).pngsave_buffer, filename: "old.png").attributes)
    @old_blob = @course.cover.blob
    edit(@exchange, "request_cover", prompt: "Show a calm landscape")
    @request = DraftCoverRequest.last
  end

  teardown { @ai.enabled, @authoring.enabled = @enabled }

  test "a successful replacement retains both blobs and can be undone" do
    assert_equal @old_blob.id, @course.reload.cover.blob.id
    assert_equal "cover_busy", assert_raises(Drafts::Error) { edit(@exchange, "update_draft", title: "Wait") }.code
    DraftCoverJob.perform_now(@request)
    assert @request.reload.completed?, @request.error_code
    new_blob = @course.reload.cover.blob
    assert_not_equal @old_blob.id, new_blob.id
    assert_equal [ @old_blob.id, new_blob.id ].sort, @request.course_change.retained_covers.blobs.ids.sort
    @exchange.finish!(:completed, answer: "Saved")
    @request.course_change.undo!(expected_revision: @course.revision)
    assert_equal @old_blob.id, @course.reload.cover.blob.id
    assert @old_blob.service.exist?(@old_blob.key)
  end

  test "a failed replacement keeps the cover and retries explicitly" do
    @ai.cover_generator.error = "unavailable"
    DraftCoverJob.perform_now(@request)
    assert @request.reload.failed?
    assert_equal @old_blob.id, @course.reload.cover.blob.id
    @exchange.finish!(:completed, answer: "Image queued")
    @ai.cover_generator.error = nil
    retry_request = @request.retry!
    DraftCoverJob.perform_now(retry_request)
    assert retry_request.reload.completed?
    assert_equal 1, CourseChange.count
  end

  test "cancellation during image generation rejects its late result" do
    @ai.cover_generator.before_finish = -> { @exchange.cancel! }
    DraftCoverJob.perform_now(@request)
    assert @request.reload.cancelled?
    assert_equal @old_blob.id, @course.reload.cover.blob.id
    assert_equal 0, CourseChange.count
  end

  test "recovery recognizes a committed replacement without another image request" do
    DraftCoverJob.perform_now(@request)
    run = AiRun.find_by!(subject: @request)
    run.update!(status: :recovering)
    history = Object.new
    history.define_singleton_method(:turn_for) { |_| raise "No remote read needed" }
    AiRecovery.new(run, history: history).call
    assert run.reload.completed?
    assert_equal 1, CourseChange.count
    assert_equal 1, @ai.cover_generator.calls.size
  end

  test "a late image cannot leave a running request with no recoverable run" do
    @ai.cover_generator.before_finish = -> { @request.update!(expires_at: 1.second.ago) }
    DraftCoverJob.perform_now(@request)
    assert @request.reload.failed?
    assert_equal "timeout", @request.error_code
    assert_equal @old_blob.id, @course.reload.cover.blob.id
    assert AiRun.find_by!(subject: @request).failed?
  end

  test "an out of band revision change rejects the generated image" do
    @ai.cover_generator.before_finish = -> { @course.update!(revision: 1, title: "Newer content") }
    DraftCoverJob.perform_now(@request)
    assert @request.reload.failed?
    assert_equal "revision_conflict", @request.error_code
    assert_equal @old_blob.id, @course.reload.cover.blob.id
    assert_equal 0, CourseChange.count
  end

  test "a stored image result recovers the replacement without another generation" do
    @request.update!(status: :recovering, expires_at: 1.minute.ago)
    run = AiRun.start!(@request, "cover", SecureRandom.uuid)
    run.update!(submitted_at: Time.current, thread_id: "image", turn_id: "image-turn", status: :recovering)
    turn = { "id" => "image-turn", "status" => "completed", "items" => [
      { "id" => "image-result", "type" => "imageGeneration", "status" => "completed",
        "result" => Base64.strict_encode64(File.binread(Rails.root.join("db/seeds/images/commute-times.png"))) }
    ] }
    history = Object.new
    history.define_singleton_method(:turn_for) { |_| turn }
    2.times { AiRecovery.new(run, history: history).call }
    assert @request.reload.completed?
    assert run.reload.completed?
    assert_equal 1, CourseChange.count
    assert_not_equal @old_blob.id, @course.reload.cover.blob.id
    assert_empty @ai.cover_generator.calls
  end
end
