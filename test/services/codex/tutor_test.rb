require "test_helper"

class CodexTutorTest < ActiveSupport::TestCase
  class Protocol
    attr_reader :calls

    def initialize
      @calls = []
    end

    def open(**options)
      yield self
    end

    def rpc(method, **params)
      @calls << [ method, params ]
      case method
      when "account/read" then { "requiresOpenaiAuth" => true, "account" => { "type" => "chatgpt" } }
      when "model/list" then { "data" => [ { "model" => LocalAi::MODEL } ] }
      when "config/read" then { "config" => { "mcp_servers" => { "example" => {} }, "plugins" => { "example@local" => {} } } }
      when "thread/start", "thread/resume" then { "model" => LocalAi::MODEL, "thread" => { "id" => "thread-1" } }
      when "turn/start" then { "turn" => { "id" => "turn-1" } }
      end
    end

    def notification
      @events ||= [
        { "method" => "item/completed", "params" => { "threadId" => "another-thread", "turnId" => "turn-1", "item" => { "type" => "agentMessage", "id" => "wrong", "text" => "Ignore this" } } },
        { "method" => "item/completed", "params" => { "threadId" => "thread-1", "turnId" => "turn-1", "item" => { "type" => "agentMessage", "id" => "answer", "phase" => "final_answer", "text" => "The answer" } } },
        { "method" => "turn/completed", "params" => { "threadId" => "thread-1", "turn" => { "id" => "turn-1", "status" => "completed" } } }
      ]
      @events.shift or raise "Unexpected event read"
    end
  end

  test "the adapter pins Sol, restricts capabilities, and sends only the explicit lesson context" do
    conversation = lessons(:pitch).conversations.create!(browser_key: SecureRandom.hex(32))
    exchange = conversation.ask!(question: "Explain pitch", request_key: SecureRandom.uuid, locale: "en")
    connection = Protocol.new

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
    assert_equal exchange.question, payload["question"]
    assert_equal "en", payload["response_language"]

    resumed = Protocol.new
    Codex::Tutor.new(connection: resumed).reply(exchange, on_thread: ->(_) { }, cancelled: -> { false })
    assert_equal "thread-1", resumed.calls.assoc("thread/resume").last[:threadId]
  end
end
