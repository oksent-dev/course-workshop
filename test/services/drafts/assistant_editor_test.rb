require "test_helper"
require_relative "../../support/draft_editing"

class DraftAssistantEditorTest < ActiveSupport::TestCase
  include DraftEditing
  include ActiveJob::TestHelper

  setup do
    @ai, @authoring = Rails.configuration.x.local_ai, Rails.configuration.x.local_authoring
    @enabled = [ @ai.enabled, @authoring.enabled ]
    @ai.enabled = @authoring.enabled = true
    @exchange = start_editor
    @course = @exchange.conversation.course
  end

  teardown { @ai.enabled, @authoring.enabled = @enabled }

  test "edits append reorder archive and undo without losing lesson identities" do
    original = Drafts::Snapshot.capture(@course)
    edit(@exchange, "save_lesson", lesson_id: lessons(:pitch).id, title: "Clearer pitch", body: BODY)
    result = edit(@exchange, "save_lesson", title: "Practice", body: BODY)
    added = Lesson.find(result.fetch("lesson").fetch("id"))
    ids = @course.lessons.reload.pluck(:id).reverse
    edit(@exchange, "reorder_lessons", lesson_ids: ids)
    assert_equal ids, @course.lessons.reload.ids
    edit(@exchange, "remove_lesson", lesson_id: lessons(:pitch).id)
    assert lessons(:pitch).reload.archived_at?
    assert_equal [ 1, 2 ], @course.lessons.reload.pluck(:position)
    @exchange.finish!(:completed, answer: "Saved")
    4.times do
      change = CourseChange.latest_undoable(@course.reload)
      assert change
      change.undo!(expected_revision: @course.revision)
    end
    assert_equal original, Drafts::Snapshot.capture(@course.reload)
    assert added.reload.archived_at?
    assert_equal 8, @course.revision
    assert_nil CourseChange.latest_undoable(@course)
  end

  test "retry receipts replay a saved edit and reject altered arguments or stale revisions" do
    arguments = { request_key: SecureRandom.uuid, expected_revision: 0, title: "Updated" }
    saved = edit(@exchange, "update_draft", **arguments)
    assert_equal saved.deep_stringify_keys, edit(@exchange, "update_draft", **arguments)
    assert_equal 1, CourseChange.count
    assert_equal "request_conflict", assert_raises(Drafts::Error) { edit(@exchange, "update_draft", **arguments.merge(title: "Different")) }.code
    assert_equal "revision_conflict", assert_raises(Drafts::Error) { edit(@exchange, "update_draft", expected_revision: 0, title: "Stale") }.code
    assert_equal "Updated", @course.reload.title
  end

  test "scope token cancellation and publication are enforced at every tool call" do
    other = courses(:composition).lessons.create!(title: "Private", body: BODY, position: 1)
    assert_raises(ActiveRecord::RecordNotFound) { edit(@exchange, "remove_lesson", lesson_id: other.id) }
    assert_raises(Drafts::Error) { Drafts::AssistantEditor.new(@exchange, token: "wrong").call("read_draft", {}) }
    assert_equal "editor_busy", assert_raises(Drafts::Error) { Drafts::Editor.publish(course_id: @course.id, expected_revision: 0) }.code
    @exchange.cancel!
    assert_raises(Drafts::Error) { edit(@exchange, "update_draft", title: "Too late") }
    assert_equal 0, @course.reload.revision
    assert other.reload
  end

  test "another learner cannot reserve a writer while this exchange is active" do
    learner = LearnerProfile.create!(key: SecureRandom.hex(32))
    other = Conversation.for_course!(course: @course, learner: learner, mode: "editor")
    assert_equal "editor_busy", assert_raises(Drafts::Error) { other.ask!(question: "Overwrite", locale: "en", request_key: SecureRandom.uuid) }.code
    @exchange.finish!(:failed, error_code: "interrupted")
    assert other.ask!(question: "Try again", locale: "en", request_key: SecureRandom.uuid).queued?
  end

  test "attachment imports cannot race an editor and expired credentials cannot write" do
    error = assert_raises(Drafts::Error) do
      CourseCovers::Import.call(course: @course, path: Rails.root.join("db/seeds/images/commute-times.png"))
    end
    assert_equal "editor_busy", error.code
    @exchange.update!(editor_expires_at: 1.second.ago)
    assert_equal "inactive_editor", assert_raises(Drafts::Error) { edit(@exchange, "update_draft", title: "Expired") }.code
    assert_equal 0, @course.reload.revision
  end

  test "invalid lessons and orders roll back the whole mutation" do
    assert_equal "missing_visual", assert_raises(Drafts::Error) { edit(@exchange, "save_lesson", title: "No visual", body: "Only text") }.code
    assert_equal "invalid_order", assert_raises(Drafts::Error) { edit(@exchange, "reorder_lessons", lesson_ids: [ lessons(:pitch).id ]) }.code
    assert_equal 0, CourseChange.count
    assert_equal 0, @course.reload.revision
  end

  test "an external edit prevents undo from overwriting newer content" do
    edit(@exchange, "update_draft", title: "First edit")
    @exchange.finish!(:completed, answer: "Saved")
    change = CourseChange.last
    Drafts::Editor.update_course(course_id: @course.id, expected_revision: 1, title: "External edit",
      description: @course.description, language: "en", category_id: @course.category_id)
    assert_nil CourseChange.latest_undoable(@course.reload)
    assert_raises(Drafts::Error) { change.undo!(expected_revision: 2) }
    assert_equal "External edit", @course.reload.title
  end

  test "plan revisions require fresh approval and preserve the approved plan as history" do
    @exchange.finish!(:completed, answer: "Done")
    generation = CourseGeneration.submit!(topic: "Patterns", language: "en", request_key: SecureRandom.uuid)
    generation.update!(status: :cancelled, plan: [ "Original" ], approved_plan: [ "Original" ], plan_approved_at: 1.minute.ago, lesson_count: 1)
    exchange = start_editor(generation.course)
    edit(exchange, "revise_plan", lesson_titles: [ "Foundations", "Practice" ])
    assert generation.reload.awaiting_approval?
    assert_nil generation.plan_approved_at
    assert_equal [ "Original" ], generation.approved_plan
    assert_equal 2, generation.lesson_count
    assert_equal "editor_busy", assert_raises(Drafts::Error) { generation.approve_plan!(generation.attempt, generation.course.reload.revision) }.code
    exchange.finish!(:completed, answer: "Review the revised plan")
    assert_not generation.approve_plan!(1, 0)
    assert generation.approve_plan!(generation.attempt, generation.course.reload.revision)
    assert_equal [ "Foundations", "Practice" ], generation.reload.approved_plan
  end

  test "a lost tool response is reconciled from its committed receipt after cancellation" do
    key = SecureRandom.uuid
    activity = @exchange.assistant_activities.create!(key: key, tool: "update_draft")
    result = edit(@exchange, "update_draft", request_key: key, title: "Already saved")
    @exchange.cancel!
    activity.reconcile!
    assert activity.completed?
    assert_equal result["change_id"], activity.course_change_id
    assert_equal "Already saved", @course.reload.title
  end

  test "recovery restores an answer while retaining saved writes and revoking the stale editor" do
    edit(@exchange, "update_draft", title: "Saved before interruption")
    run = AiRun.start!(@exchange, "reply", SecureRandom.uuid)
    run.update!(submitted_at: Time.current, thread_id: "editor", turn_id: "edit-turn", status: :recovering)
    turn = { "id" => "edit-turn", "status" => "completed", "items" => [
      { "id" => "answer", "type" => "agentMessage", "phase" => "final_answer", "text" => "Title saved" }
    ] }
    history = Object.new
    history.define_singleton_method(:turn_for) { |_| turn }
    2.times { AiRecovery.new(run, history: history).call }
    assert @exchange.reload.completed?
    assert_equal "Title saved", @exchange.answer
    assert_nil @exchange.editor_token_digest
    assert_equal 1, CourseChange.count
    assert_equal "Saved before interruption", @course.reload.title
    assert_raises(Drafts::Error) { edit(@exchange, "update_draft", title: "Late write") }
  end

  test "MCP exposes only scoped editor capabilities and reports committed changes" do
    server = CourseMcp::EditorServer.new(exchange_id: @exchange.id, token: @token)
    assert server.build
    response = server.execute("update_draft", request_key: SecureRandom.uuid, expected_revision: 0, title: "Saved through MCP")
    assert_not response.error?
    assert_equal "Saved through MCP", @course.reload.title
    assert @exchange.assistant_activities.last.completed?
    denied = server.execute("publish_course", {})
    assert denied.error?
    assert @course.reload.draft?
  end
end
