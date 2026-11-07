require "test_helper"
require_relative "../support/fake_tutor"

class CourseAssistantTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    host! "localhost"
    @ai = Rails.configuration.x.local_ai
    @authoring = Rails.configuration.x.local_authoring
    @previous = [ @ai.enabled, @ai.adapter, @authoring.enabled ]
    @ai.enabled = @authoring.enabled = true
    @ai.adapter = FakeTutor.new
    @local = { "REMOTE_ADDR" => "127.0.0.1" }
    @course = courses(:listening)
  end

  teardown { @ai.enabled, @ai.adapter, @authoring.enabled = @previous }

  test "outline and lesson questions share history with distinct immutable context" do
    perform_enqueued_jobs { ask("Where should I start?") }
    overview = Exchange.last
    assert_nil overview.lesson_context["body"]
    assert_nil overview.lesson_context["lesson_id"]
    assert_equal @course.description, overview.lesson_context["description"]
    assert_equal %w[Pitch Rhythm], overview.lesson_context["outline"].map { |entry| entry["title"] }

    perform_enqueued_jobs { ask("Explain rhythm", context_lesson_id: lessons(:rhythm).id) }
    assert_equal overview.conversation_id, Exchange.last.conversation_id
    assert_equal lessons(:rhythm).body, Exchange.last.lesson_context["body"]
    get course_conversation_path(@course, locale: :en), headers: @local
    assert_includes response.parsed_body["html"], "Where should I start?"
    assert_includes response.parsed_body["html"], "Course outline"
  end

  test "quote origin stays attached and stale content cannot be silently substituted" do
    version = AssistantContext.version(@course)
    key = SecureRandom.uuid
    input = { context_lesson_id: lessons(:pitch).id, selected_text: "a high note", selection_version: version, request_key: key }
    perform_enqueued_jobs { ask("Explain this", **input) }
    original = Exchange.last
    lessons(:pitch).update!(body: "Changed after the selection")
    assert_no_enqueued_jobs { ask("Explain this", **input) }
    assert_response :success
    assert_equal 1, Exchange.count
    assert_equal "a high note", original.reload.selected_text
    assert_no_enqueued_jobs { ask("Another question", **input.merge(request_key: SecureRandom.uuid)) }
    assert_response :conflict
    assert_includes response.parsed_body["error"], "material has changed"
  end

  test "another course's lesson and conversation cannot be addressed" do
    other = courses(:composition).lessons.create!(position: 1, title: "Private", body: "Other material")
    assert_no_enqueued_jobs { ask("Explain", context_lesson_id: other.id) }
    assert_response :not_found
    ask("A pending question")
    exchange = Exchange.last
    delete course_conversation_exchange_path(courses(:composition), exchange, locale: :en), headers: @local
    assert_response :not_found
    assert exchange.reload.queued?
  end

  test "draft discussion is local, read only and separate after publication" do
    @course.update!(status: :draft)
    perform_enqueued_jobs { ask("A private improvement idea", mode: "editor") }
    editor = Exchange.last
    assert_equal "editor", editor.conversation.mode
    assert_equal "editor", @ai.adapter.calls.last[:context]["mode"]
    assert_equal 0, @course.reload.revision
    @course.update!(status: :published)

    get course_conversation_path(@course, locale: :en), headers: @local
    assert_not_includes response.parsed_body["html"], "A private improvement idea"
    assert_no_enqueued_jobs { ask("From an old draft tab", mode: "editor") }
    assert_response :conflict
    assert_equal 1, Exchange.count
    assert_equal "A private improvement idea", editor.reload.question
    assert_no_enqueued_jobs { ask("Pretend to edit", mode: "editor") }
    assert_response :conflict
  end

  test "draft endpoints require authoring as well as AI and loopback access" do
    @course.update!(status: :draft)
    @authoring.enabled = false
    assert_no_enqueued_jobs { ask("Explain") }
    assert_response :not_found
    @authoring.enabled = true
    post course_conversation_exchanges_path(@course, locale: :en),
      params: { question: "Explain", request_key: SecureRandom.uuid }, headers: { "REMOTE_ADDR" => "203.0.113.1" }
    assert_response :not_found
    assert_equal 0, Exchange.count
  end

  test "persisted generation activity can be reconstructed without an inference" do
    generation = CourseGeneration.submit!(topic: "Sound", language: "en", request_key: SecureRandom.uuid)
    @course = generation.course
    generation.update!(status: :running, activity: "researching")
    get course_conversation_path(@course, locale: :en), headers: @local
    assert_response :success
    assert_includes response.parsed_body["activity_html"], "Checking sources online"
    assert_includes response.parsed_body["activity_html"], "generation-#{generation.id}"
    assert_empty @ai.adapter.calls
    perform_enqueued_jobs { ask("What is the scope?", mode: "editor") }
    assert_equal "Sound", Exchange.last.lesson_context.dig("generation", "topic")
    assert_nil Exchange.last.lesson_context["body"]
  end

  test "content versions and removed lesson identifiers support safe view refresh" do
    get course_conversation_path(@course, locale: :en), headers: @local
    original = response.parsed_body
    lessons(:pitch).destroy!
    get course_conversation_path(@course, locale: :en), headers: @local
    assert_not_equal original["version"], response.parsed_body["version"]
    assert_equal [ lessons(:rhythm).id ], response.parsed_body["lesson_ids"]
    assert_equal course_path(@course, locale: :en), response.parsed_body["overview_url"]
  end

  private

  def ask(question, **params)
    post course_conversation_exchanges_path(@course, locale: :en),
      params: { question: question, request_key: SecureRandom.uuid }.merge(params), headers: @local
  end
end
