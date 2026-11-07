require "test_helper"
require_relative "../../support/fake_codex_protocol"
require_relative "../../support/draft_editing"

class CodexEditorTest < ActiveSupport::TestCase
  include DraftEditing

  test "an editor resumes its conversation with only course scoped tools" do
    enabled = [ Rails.configuration.x.local_ai.enabled, Rails.configuration.x.local_authoring.enabled ]
    Rails.configuration.x.local_ai.enabled = Rails.configuration.x.local_authoring.enabled = true
    exchange = start_editor
    conversation = exchange.conversation
    conversation.update!(runtime_thread_id: "editor-thread")
    connection = FakeCodexProtocol.new
    Codex::Editor.new(connection: connection).reply(exchange, token: @token,
      on_thread: ->(_) { }, cancelled: -> { false })
    start = connection.calls.assoc("thread/resume").last
    assert_equal "editor-thread", start[:threadId]
    assert_equal "gpt-6.1-sol", start[:model]
    assert_equal "read-only", start[:sandbox]
    config = start[:config]
    assert_equal false, config["features.shell_tool"]
    assert_equal false, config["mcp_servers.example.enabled"]
    assert_equal CourseMcp::EditorServer::TOOL_NAMES, config["mcp_servers.course_editor.enabled_tools"]
    assert_equal exchange.id.to_s, config["mcp_servers.course_editor.env"]["COURSE_EDITOR_EXCHANGE_ID"]
    assert_equal "approve", config["mcp_servers.course_editor.default_tools_approval_mode"]
    assert_not_includes config["mcp_servers.course_editor.enabled_tools"], "publish_course"
    payload = JSON.parse(connection.calls.assoc("turn/start").last[:input].first[:text])
    assert_equal exchange.lesson_context, payload["lesson"]
    assert payload["current_draft"]
  ensure
    Rails.configuration.x.local_ai.enabled, Rails.configuration.x.local_authoring.enabled = enabled
  end
end
