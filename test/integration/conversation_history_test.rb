require "test_helper"
require_relative "../support/conversation_history"

class ConversationHistoryTest < ActionDispatch::IntegrationTest
  include ConversationHistory

  setup do
    host! "localhost"
    @ai = Rails.configuration.x.local_ai
    @previous_enabled = @ai.enabled
    @ai.enabled = true
    @local = { "REMOTE_ADDR" => "127.0.0.1" }
    @course = courses(:listening)
    fetch_history
    @conversation = Conversation.find_by!(course: @course, mode: "tutor", legacy: false)
    @exchanges = saved_exchanges(@conversation, 45)
  end

  teardown { @ai.enabled = @previous_enabled }

  test "history starts with twenty latest exchanges and pages backwards without gaps" do
    fetch_history
    assert_equal @exchanges.last(20).map(&:id), rendered_ids
    assert_equal @exchanges[25].id, response.parsed_body["next_before"]

    fetch_history(before: response.parsed_body["next_before"])
    assert_equal @exchanges[5, 20].map(&:id), rendered_ids
    fetch_history(before: response.parsed_body["next_before"])
    assert_equal @exchanges.first(5).map(&:id), rendered_ids
    assert_nil response.parsed_body["next_before"]
    assert_equal 45, @conversation.history.count
  end

  test "refresh retains the loaded window and pending state is independent of the history page" do
    pending = @conversation.ask!(question: "A new question", request_key: SecureRandom.uuid, locale: "en")
    fetch_history(before: @exchanges[5].id)
    assert_equal @exchanges.first(5).map(&:id), rendered_ids
    assert response.parsed_body["busy"]
    assert_includes response.parsed_body["cancel_url"], pending.id.to_s

    fetch_history(from: @exchanges[5].id)
    assert_equal (@exchanges.drop(5) + [ pending ]).map(&:id), rendered_ids
    pending.update!(status: :completed, answer: "The final answer")
    fetch_history(from: @exchanges[5].id)
    assert_not response.parsed_body["busy"]
    assert_includes response.parsed_body["html"], "The final answer"
  end

  test "cursors must belong to this course owner and mode and are checked before mutations" do
    other_owner = LearnerProfile.create!(key: SecureRandom.hex(32))
    conversations = [
      Conversation.for_course!(course: courses(:composition), learner: @conversation.learner_profile),
      Conversation.for_course!(course: @course, learner: other_owner),
      Conversation.for_course!(course: @course, learner: @conversation.learner_profile, mode: "editor")
    ]
    conversations.each do |conversation|
      foreign_id = saved_exchanges(conversation, 1).first.id
      %i[before from].each do |cursor|
        get course_conversation_path(@course, locale: :en), params: { cursor => foreign_id }, headers: @local
        assert_response :not_found
      end
      assert_no_difference "Exchange.count" do
        post course_conversation_exchanges_path(@course, locale: :en),
          params: { from: foreign_id, question: "Must not be saved", request_key: SecureRandom.uuid }, headers: @local
        assert_response :not_found
      end
    end

    [ { before: "invalid" }, { before: "0" }, { before: @exchanges.first.id, from: @exchanges.first.id }, { from: [ @exchanges.first.id ] } ].each do |params|
      get course_conversation_path(@course, locale: :en), params: params, headers: @local
      assert_response :bad_request
    end
  end

  test "an owned legacy lesson conversation remains part of paginated history" do
    legacy = Conversation.create!(course: @course, lesson: lessons(:pitch), learner_profile: @conversation.learner_profile,
      mode: "tutor", legacy: true, browser_key: SecureRandom.hex(32))
    old_exchange = saved_exchanges(legacy, 1).first
    fetch_history
    assert_equal (@exchanges.last(19) + [ old_exchange ]).map(&:id), rendered_ids
    fetch_history(before: old_exchange.id)
    assert_equal @exchanges.last(20).map(&:id), rendered_ids
  end

  private

  def fetch_history(**params)
    get course_conversation_path(@course, locale: :en), params: params, headers: @local
    assert_response :success
  end

  def rendered_ids
    Nokogiri::HTML.fragment(response.parsed_body["html"]).css("[data-exchange-id]").map { |item| item["data-exchange-id"].to_i }
  end
end
