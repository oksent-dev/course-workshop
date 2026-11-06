require "test_helper"
require "open3"

class CourseMcpStdioTest < ActiveSupport::TestCase
  test "the real launcher negotiates MCP and reserves stdout for JSON lines" do
    requests = [
      { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "test", version: "1" } } },
      { jsonrpc: "2.0", method: "notifications/initialized" },
      { jsonrpc: "2.0", id: 2, method: "tools/list" }
    ]
    output, error, status = Open3.capture3({ "RAILS_ENV" => "test", "COURSE_AUTHORING_ENABLED" => "true" },
      RbConfig.ruby, Rails.root.join("bin/mcp").to_s, stdin_data: requests.map(&:to_json).join("\n") + "\n")
    assert status.success?, error
    replies = output.lines.map { |line| JSON.parse(line) }
    assert_equal [ 1, 2 ], replies.map { |reply| reply["id"] }
    assert_equal "course_workshop", replies.first.dig("result", "serverInfo", "name")
    assert_equal 9, replies.last.dig("result", "tools").size
  end

  test "the launcher refuses to expose tools when disabled" do
    output, error, status = Open3.capture3({ "RAILS_ENV" => "test", "COURSE_AUTHORING_ENABLED" => "false" },
      RbConfig.ruby, Rails.root.join("bin/mcp").to_s, stdin_data: "")
    assert_not status.success?
    assert_empty output
    assert_includes error, "COURSE_AUTHORING_ENABLED=true"
  end
end
