require "test_helper"
require "base64"
require_relative "../../support/fake_codex_protocol"

class CodexCoverGeneratorTest < ActiveSupport::TestCase
  setup do
    @connection = FakeCodexProtocol.new
    @adapter = Codex::CoverGenerator.new(connection: @connection)
    @bytes = File.binread(Rails.root.join("db/seeds/images/commute-times.png"))
  end

  test "only the matching image tool result is decoded with all other tools disabled" do
    events = [ image_event(turn: "old-turn", result: "bad"), image_event(result: Base64.strict_encode64(@bytes)), completed ]
    @connection.define_singleton_method(:notification) { events.shift || raise("Unexpected event read") }
    upload = @adapter.generate(courses(:listening), cancelled: -> { false })
    assert_equal @bytes, upload.attributes[:io].read
    assert_equal CourseCoverGeneration::TIMEOUT, @connection.open_options[:timeout]
    params = @connection.calls.assoc("thread/start").last
    assert_equal LocalAi::DEFAULT_MODEL, params[:model]
    assert_equal "never", params[:approvalPolicy]
    assert_equal "read-only", params[:sandbox]
    assert_equal true, params[:config]["features.image_generation"]
    assert_equal false, params[:config]["features.shell_tool"]
    assert_equal false, params[:config]["mcp_servers.example.enabled"]
    assert_equal "disabled", params[:config]["web_search"]
  end

  test "missing invalid oversized and quota limited results are retryable errors without reading paths" do
    [
      [ nil, "invalid_image" ],
      [ { result: "not base64", savedPath: __FILE__ }, "invalid_image" ],
      [ { result: "A" * (ImageUpload::MAX_BYTES * 2) }, "invalid_image" ],
      [ { result: Base64.strict_encode64("<svg/>") }, ImageUpload::InvalidImage ],
      [ { failure: { type: "usageLimitExceeded" }, status: "failed" }, "usage_limit" ]
    ].each do |item, expected|
      events = [ (image_event(**item) if item), completed ].compact
      @connection.define_singleton_method(:notification) { events.shift || raise("Unexpected event read") }
      error = assert_raises(expected.is_a?(Class) ? expected : LocalAi::Error) do
        @adapter.generate(courses(:listening), cancelled: -> { false })
      end
      assert_equal expected, error.code if expected.is_a?(String)
    end
  end

  test "cancellation interrupts the current turn" do
    @connection.define_singleton_method(:notification) { raise LocalAi::Cancelled }
    assert_raises(LocalAi::Cancelled) { @adapter.generate(courses(:listening), cancelled: -> { true }) }
    assert @connection.calls.assoc("turn/interrupt")
  end

  private

  def image_event(turn: "turn-1", **item)
    { "method" => "item/completed", "params" => { "threadId" => "thread-1", "turnId" => turn,
      "item" => { "type" => "imageGeneration", "status" => "completed" }.merge(item.deep_stringify_keys) } }
  end

  def completed
    { "method" => "turn/completed", "params" => { "threadId" => "thread-1", "turn" => { "id" => "turn-1", "status" => "completed" } } }
  end
end
