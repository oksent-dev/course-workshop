require "test_helper"
require_relative "../../support/fake_codex_protocol"

class CodexTutorTest < ActiveSupport::TestCase
  test "the adapter pins Sol, restricts capabilities, and sends only the explicit lesson context" do
    conversation = lessons(:pitch).conversations.create!(browser_key: SecureRandom.hex(32))
    exchange = conversation.ask!(question: "Explain pitch", selected_text: "a high note", request_key: SecureRandom.uuid, locale: "en")
    connection = FakeCodexProtocol.new

    answer = Codex::Tutor.new(connection: connection).reply(exchange,
      on_thread: ->(id) { conversation.update!(runtime_thread_id: id) }, cancelled: -> { false })
    assert_equal "The answer", answer

    start = connection.calls.assoc("thread/start").last
    assert_equal "gpt-6.1-sol", start[:model]
    assert_equal "read-only", start[:sandbox]
    assert_equal false, start[:config]["features.shell_tool"]
    assert_equal false, start[:config]["mcp_servers.example.enabled"]
    assert_equal false, start[:config]["plugins.example@local.enabled"]
    assert_equal 0, start[:config]["project_doc_max_bytes"]
    turn = connection.calls.assoc("turn/start").last
    payload = JSON.parse(turn[:input].first[:text])
    assert_equal exchange.lesson_context, payload["lesson"]
    assert_equal "a high note", payload["lesson"]["selected_text"]
    assert_equal exchange.question, payload["question"]
    assert_equal "en", payload["response_language"]

    resumed = FakeCodexProtocol.new
    Codex::Tutor.new(connection: resumed).reply(exchange, on_thread: ->(_) { }, cancelled: -> { false })
    assert_equal "thread-1", resumed.calls.assoc("thread/resume").last[:threadId]
  end
end
