require "test_helper"
require_relative "../support/fake_tutor"

class LessonConversationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    host! "localhost"
    @settings = Rails.configuration.x.local_ai
    @previous_enabled, @previous_adapter = @settings.enabled, @settings.adapter
    @settings.enabled = true
    @settings.adapter = @tutor = FakeTutor.new
    @lesson = lessons(:pitch)
    @path = course_lesson_conversation_path(@lesson.course, @lesson, locale: :en)
    @create_path = course_lesson_conversation_exchanges_path(@lesson.course, @lesson, locale: :en)
    @local = { "REMOTE_ADDR" => "127.0.0.1" }
  end

  teardown do
    @settings.enabled, @settings.adapter = @previous_enabled, @previous_adapter
  end

  test "a question carries a lesson snapshot and a follow-up resumes the same thread" do
    perform_enqueued_jobs { ask("Explain pitch.") }
    assert_response :success
    first = Exchange.last
    assert_equal @lesson.body, first.lesson_context["body"]
    assert_equal "completed", first.status
    assert_equal @tutor.answer, first.answer
    assert_equal "en", @tutor.calls.first[:locale]

    @lesson.update!(body: "Updated material.")
    perform_enqueued_jobs { ask("Can you give another example?") }
    assert_equal "fake-thread-#{first.conversation_id}", @tutor.calls.last[:thread_id]
    assert_equal "Updated material.", @tutor.calls.last[:context]["body"]

    get @path, headers: @local
    assert_includes response.parsed_body["html"], @tutor.answer
    assert_equal false, response.parsed_body["busy"]
  end

  test "conversations are isolated by lesson and browser" do
    perform_enqueued_jobs { ask("Private question") }
    other = lessons(:rhythm)
    get course_lesson_conversation_path(other.course, other, locale: :en), headers: @local
    assert_not_includes response.parsed_body["html"], "Private question"

    new_browser = open_session
    new_browser.host! "localhost"
    new_browser.get @path, headers: @local
    assert_not_includes new_browser.response.parsed_body["html"], "Private question"

    @settings.enabled = false
    get @path, headers: @local
    assert_response :not_found
  end

  test "disabled AI and nonlocal requests cannot enqueue work" do
    @settings.enabled = false
    assert_no_enqueued_jobs { ask("Explain pitch") }
    assert_response :not_found
    assert_equal 0, Conversation.count

    @settings.enabled = true
    assert_no_enqueued_jobs { post @create_path, params: { question: "Explain", request_key: SecureRandom.uuid }, headers: { "REMOTE_ADDR" => "203.0.113.1" } }
    assert_response :not_found

    host! "example.com"
    assert_no_enqueued_jobs { ask("Explain pitch") }
    assert_response :not_found
  end

  test "duplicate submissions are idempotent and a pending turn blocks another question" do
    key = SecureRandom.uuid
    assert_enqueued_jobs 1 do
      ask("Explain pitch", key: key)
      ask("Explain pitch", key: key)
    end
    assert_equal 1, Exchange.count
    ask("Another question")
    assert_response :conflict
    assert_equal 1, Exchange.count
  end

  test "invalid questions and a lesson from another course are rejected" do
    [ " ", "a" * 4001 ].each do |question|
      assert_no_enqueued_jobs { ask(question) }
      assert_response :unprocessable_content
    end

    post course_lesson_conversation_exchanges_path(courses(:composition), @lesson, locale: :en),
      params: { question: "Explain", request_key: SecureRandom.uuid }, headers: @local
    assert_response :not_found
  end

  test "unavailable runtime is a visible failure and can be retried" do
    @tutor.error = "unavailable"
    perform_enqueued_jobs { ask("Explain pitch") }
    assert_equal "failed", Exchange.last.status

    get @path, headers: @local
    assert_includes response.parsed_body["html"], "The local tutor is unavailable."
    assert_equal false, response.parsed_body["busy"]

    @tutor.error = nil
    perform_enqueued_jobs { ask("Explain pitch") }
    assert_equal "completed", Exchange.last.status
  end

  test "cancelling queued work prevents a runtime call" do
    ask("Explain pitch")
    exchange = Exchange.last
    delete course_lesson_conversation_exchange_path(@lesson.course, @lesson, exchange, locale: :en), headers: @local
    assert_response :success
    perform_enqueued_jobs
    assert exchange.reload.cancelled?
    assert_empty @tutor.calls
  end

  test "a restart does not leave an old queued question blocking the conversation forever" do
    ask("Explain pitch")
    exchange = Exchange.last
    exchange.update!(created_at: 6.minutes.ago)

    get @path, headers: @local
    assert exchange.reload.failed?
    assert_equal "timeout", exchange.error_code
    assert_equal false, response.parsed_body["busy"]
    perform_enqueued_jobs
    assert_empty @tutor.calls
  end

  test "questions and model output are escaped" do
    @tutor.answer = "<script>alert(1)</script>"
    perform_enqueued_jobs { ask("<img src=x onerror=alert(1)>") }
    get @path, headers: @local
    fragment = Nokogiri::HTML.fragment(response.parsed_body["html"])
    assert_empty fragment.css("script, img")
    assert_includes fragment.text, @tutor.answer
  end

  private

  def ask(question, key: SecureRandom.uuid)
    post @create_path, params: { question: question, request_key: key }, headers: @local
  end
end
