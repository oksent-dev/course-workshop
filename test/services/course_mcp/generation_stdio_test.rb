require "test_helper"
require "open3"

class CourseMcpGenerationStdioTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "the scoped launcher authenticates its attempt and only exposes generation tools" do
    generation = CourseGeneration.submit!(topic: "Stdio test", language: "en", request_key: SecureRandom.uuid)
    token = generation.claim!(1)
    requests = [
      { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "test", version: "1" } } },
      { jsonrpc: "2.0", method: "notifications/initialized" },
      { jsonrpc: "2.0", id: 2, method: "tools/list" },
      { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "read_generation", arguments: {} } }
    ]
    env = { "RAILS_ENV" => "test", "LOCAL_AI_ENABLED" => "true", "COURSE_AUTHORING_ENABLED" => "true",
      "COURSE_GENERATION_ID" => generation.id.to_s, "COURSE_GENERATION_TOKEN" => token }
    output, error, status = Open3.capture3(env, RbConfig.ruby, Rails.root.join("bin/generation-mcp").to_s,
      stdin_data: requests.map(&:to_json).join("\n") + "\n")
    assert status.success?, error
    replies = output.lines.map { |line| JSON.parse(line) }
    assert_equal [ 1, 2, 3 ], replies.map { |reply| reply["id"] }
    assert_equal CourseMcp::GenerationServer::TOOL_NAMES.sort, replies[1].dig("result", "tools").map { |tool| tool["name"] }.sort
    assert_equal generation.course_id, replies[2].dig("result", "structuredContent", "course", "id")
    generation.cancel!(1)
    output, _, status = Open3.capture3(env, RbConfig.ruby, Rails.root.join("bin/generation-mcp").to_s, stdin_data: "")
    assert_not status.success?
    assert_empty output
  ensure
    generation&.course&.destroy!
  end
end
