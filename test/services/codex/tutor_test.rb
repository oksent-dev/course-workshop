require "test_helper"
require_relative "../../support/fake_codex_protocol"

class CodexTutorTest < ActiveSupport::TestCase
  test "a missing runtime thread is rebuilt from saved application messages" do
    conversation = lessons(:pitch).conversations.create!(browser_key: SecureRandom.hex(32), runtime_thread_id: "missing-thread")
    previous = conversation.ask!(question: "First question", request_key: SecureRandom.uuid, locale: "en")
    previous.finish!(:completed, answer: "Saved response")
    exchange = conversation.ask!(question: "Continue", request_key: SecureRandom.uuid, locale: "en")
    run = AiRun.start!(exchange, "reply", SecureRandom.uuid)
    connection = FakeCodexProtocol.new
    original_rpc = connection.method(:rpc)
    connection.define_singleton_method(:rpc) do |method, **params|
      raise Codex::RpcError.new("code" => -32600, "message" => "thread not found") if method == "thread/resume"
      original_rpc.call(method, **params)
    end

    Codex::Tutor.new(connection: connection).reply(exchange, run: run,
      on_thread: ->(id) { conversation.update!(runtime_thread_id: id) }, cancelled: -> { false })
    assert run.reload.thread_replaced?
    assert_equal "thread-1", run.thread_id
    assert_equal "turn-1", run.turn_id
    assert run.submitted_at?
    assert_equal [ "answer" ], run.item_ids
    payload = JSON.parse(connection.calls.assoc("turn/start").last[:input].first[:text])
    assert_equal run.id.to_s, payload["app_request_id"]
    assert_equal "Saved response", payload["restored_history"].first["answer"]
    assert_equal "Saved response", previous.reload.answer
  end

  test "a transient resume error does not start a replacement thread" do
    conversation = lessons(:pitch).conversations.create!(browser_key: SecureRandom.hex(32), runtime_thread_id: "known-thread")
    exchange = conversation.ask!(question: "Continue", request_key: SecureRandom.uuid, locale: "en")
    connection = FakeCodexProtocol.new
    original_rpc = connection.method(:rpc)
    connection.define_singleton_method(:rpc) do |method, **params|
      raise Codex::RpcError.new("code" => -32603, "message" => "storage temporarily unavailable") if method == "thread/resume"
      original_rpc.call(method, **params)
    end
    assert_raises(Codex::RpcError) do
      Codex::Tutor.new(connection: connection).reply(exchange, on_thread: ->(_) { }, cancelled: -> { false })
    end
    assert_nil connection.calls.assoc("thread/start")
    assert_nil connection.calls.assoc("turn/start")
  end

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
