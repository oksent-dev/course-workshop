require "test_helper"
require_relative "../support/draft_editing"
require_relative "../support/conversation_history"

class DraftEditingTest < ActionDispatch::IntegrationTest
  include DraftEditing
  include ConversationHistory

  setup do
    host! "localhost"
    @ai, @authoring = Rails.configuration.x.local_ai, Rails.configuration.x.local_authoring
    @enabled = [ @ai.enabled, @authoring.enabled ]
    @ai.enabled = @authoring.enabled = true
    @local = { "REMOTE_ADDR" => "127.0.0.1" }
    @course = courses(:listening)
    @course.update!(status: :draft)
    post course_conversation_exchanges_path(@course, locale: :en),
      params: { question: "Change the title", request_key: SecureRandom.uuid, mode: "editor" }, headers: @local
    @exchange = Exchange.last
    activate_editor(@exchange)
    edit(@exchange, "update_draft", title: "A clearer title")
    @exchange.finish!(:completed, answer: "Updated the title")
    @change = CourseChange.last
  end

  teardown { @ai.enabled, @authoring.enabled = @enabled }

  test "saved change cards include previews and undo is idempotent across retries" do
    get course_conversation_path(@course, locale: :en), headers: @local
    assert_response :success
    html = response.parsed_body["html"]
    assert_includes html, "A clearer title"
    assert_includes html, "data-change-preview"
    assert_includes html, "Undo this change"
    2.times do
      post undo_change_course_conversation_path(@course, change_id: @change.id, locale: :en, mode: "editor"),
        params: { expected_revision: 1 }, headers: @local
      assert_response :success
    end
    assert_equal 2, CourseChange.count
    assert_not_equal "A clearer title", @course.reload.title
    assert_includes response.parsed_body["html"], "Change undone"
  end

  test "undo cannot address another learner's change" do
    foreign = ActionDispatch::Integration::Session.new(Rails.application)
    foreign.host! "localhost"
    foreign.post undo_change_course_conversation_path(@course, change_id: @change.id, locale: :en, mode: "editor"),
      params: { expected_revision: 1 }, headers: @local
    assert_equal 404, foreign.response.status
    assert_equal "A clearer title", @course.reload.title
  end

  test "a quoted selection is rejected after a saved edit without queueing work" do
    post course_conversation_exchanges_path(@course, locale: :en),
      params: { question: "Edit this", selected_text: "old text", selection_version: "old-version",
                context_lesson_id: lessons(:pitch).id, request_key: SecureRandom.uuid, mode: "editor" }, headers: @local
    assert_response :conflict
    assert_equal 1, Exchange.count
  end

  test "cover retry and cancellation are scoped durable and idempotent" do
    failed = @course.draft_cover_requests.create!(exchange: @exchange, prompt: "A quieter cover", expected_revision: 1, status: :failed)
    2.times do
      post retry_cover_course_conversation_path(@course, cover_id: failed.id, locale: :en, mode: "editor"), headers: @local
      assert_response :success
    end
    assert_equal 2, DraftCoverRequest.count
    assert response.parsed_body["editor_blocked"]
    retry_request = DraftCoverRequest.last
    delete cancel_cover_course_conversation_path(@course, cover_id: retry_request.id, locale: :en, mode: "editor"), headers: @local
    assert_response :success
    assert_not response.parsed_body["editor_blocked"]
    assert retry_request.reload.cancelled?
  end

  test "a view refresh request applies only to its saved revision" do
    activate_editor(@exchange)
    server = CourseMcp::EditorServer.new(exchange_id: @exchange.id, token: @token)
    server.execute("refresh_course_view", request_key: SecureRandom.uuid, expected_revision: 1)
    @exchange.finish!(:completed, answer: "Refresh requested")
    get course_conversation_path(@course, locale: :en), headers: @local
    assert response.parsed_body["refresh_requested"]
    @course.update!(title: "Later external change", revision: 2)
    get course_conversation_path(@course, locale: :en), headers: @local
    assert_not response.parsed_body["refresh_requested"]
  end

  test "older editing receipts keep refresh state and undo after pagination" do
    activate_editor(@exchange)
    CourseMcp::EditorServer.new(exchange_id: @exchange.id, token: @token)
      .execute("refresh_course_view", request_key: SecureRandom.uuid, expected_revision: 1)
    @exchange.finish!(:completed, answer: "Refresh requested")
    saved_exchanges(@exchange.conversation, 20)

    get course_conversation_path(@course, locale: :en), headers: @local
    assert response.parsed_body["refresh_requested"]
    assert_not_includes response.parsed_body["html"], "data-change-preview"
    get course_conversation_path(@course, locale: :en), params: { before: response.parsed_body["next_before"] }, headers: @local
    assert_includes response.parsed_body["html"], "Undo this change"

    post undo_change_course_conversation_path(@course, change_id: @change.id, locale: :en, mode: "editor", from: @exchange.id),
      params: { expected_revision: 1 }, headers: @local
    assert_response :success
    assert_equal 21, Nokogiri::HTML.fragment(response.parsed_body["html"]).css("[data-exchange-id]").size
    assert_includes response.parsed_body["html"], "Change undone"
    assert_not response.parsed_body["refresh_requested"]
  end
end
