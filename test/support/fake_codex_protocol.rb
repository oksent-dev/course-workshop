class FakeCodexProtocol
  attr_reader :calls, :open_options

  def initialize
    @calls = []
  end

  def open(**options)
    @open_options = options
    yield self
  end

  def interrupt(thread_id, turn_id)
    @calls << [ "turn/interrupt", { thread_id: thread_id, turn_id: turn_id } ]
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
