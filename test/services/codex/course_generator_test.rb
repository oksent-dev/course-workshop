require "test_helper"
require_relative "../../support/fake_codex_protocol"

class CodexCourseGeneratorTest < ActiveSupport::TestCase
  test "the generator grants only its scoped MCP tools and uses a fresh thread on retry" do
    generation = CourseGeneration.submit!(topic: "Active Record", language: "pl", lesson_count: 4, request_key: SecureRandom.uuid)
    2.times do
      connection = FakeCodexProtocol.new
      Codex::CourseGenerator.new(connection: connection).generate(generation, token: "attempt-token", cancelled: -> { false })
      assert_equal CourseGeneration::TIMEOUT, connection.open_options[:timeout]
      params = connection.calls.assoc("thread/start").last
      assert_equal "gpt-6.1-sol", params[:model]
      assert_equal "read-only", params[:sandbox]
      assert_equal "never", params[:approvalPolicy]
      assert_equal false, params[:config]["mcp_servers.example.enabled"]
      assert_equal false, params[:config]["features.shell_tool"]
      assert_equal "live", params[:config]["web_search"]
      assert_equal "approve", params[:config]["mcp_servers.course_generation.default_tools_approval_mode"]
      assert_equal CourseMcp::GenerationServer::TOOL_NAMES, params[:config]["mcp_servers.course_generation.enabled_tools"]
      env = params[:config]["mcp_servers.course_generation.env"]
      assert_equal generation.id.to_s, env["COURSE_GENERATION_ID"]
      assert_equal "attempt-token", env["COURSE_GENERATION_TOKEN"]
      turn = connection.calls.assoc("turn/start").last
      payload = JSON.parse(turn[:input].first[:text])
      assert_equal({ "topic" => "Active Record", "language" => "pl", "lesson_count" => 4 }, payload)
      assert_nil connection.calls.assoc("thread/resume")
    end
  end

  test "cancellation interrupts the active turn before the connection closes" do
    generation = CourseGeneration.submit!(topic: "Active Record", language: "en", lesson_count: 3, request_key: SecureRandom.uuid)
    connection = FakeCodexProtocol.new
    connection.define_singleton_method(:notification) { raise LocalAi::Cancelled }
    assert_raises(LocalAi::Cancelled) do
      Codex::CourseGenerator.new(connection: connection).generate(generation, token: "attempt-token", cancelled: -> { true })
    end
    assert_equal({ thread_id: "thread-1", turn_id: "turn-1" }, connection.calls.assoc("turn/interrupt").last)
  end
end
