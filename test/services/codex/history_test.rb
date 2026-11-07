require "test_helper"
require_relative "../../support/fake_codex_protocol"

class CodexHistoryTest < ActiveSupport::TestCase
  test "history pagination matches a recorded turn, never the latest unrelated answer" do
    connection = FakeCodexProtocol.new
    pages = [
      { "data" => [ { "id" => "unrelated" } ], "nextCursor" => "older" },
      { "data" => [ { "id" => "wanted", "status" => "completed" } ], "nextCursor" => nil }
    ]
    connection.define_singleton_method(:rpc) do |method, **params|
      @calls << [ method, params ]
      pages.shift
    end
    run = AiRun.new(thread_id: "mapped-thread", turn_id: "wanted")
    result = Codex::History.new(connection: connection).turn_for(run)
    assert_equal "wanted", result["id"]
    assert_equal [ "thread/turns/list" ], connection.calls.map(&:first).uniq
    assert_equal "older", connection.calls.last.last[:cursor]
    assert_equal "mapped-thread", connection.calls.first.last[:threadId]
  end

  test "a lost turn start acknowledgement is matched by the persisted request marker" do
    connection = FakeCodexProtocol.new
    items = [ { "type" => "userMessage", "content" => [
      { "type" => "text", "text" => JSON.generate(app_request_id: "123", question: "Explain") }
    ] } ]
    connection.define_singleton_method(:rpc) do |_, **_|
      { "data" => [ { "id" => "unrelated", "items" => [] }, { "id" => "found", "items" => items } ] }
    end
    run = AiRun.new(id: 123, thread_id: "mapped-thread")
    assert_equal "found", Codex::History.new(connection: connection).turn_for(run)["id"]
  end
end
