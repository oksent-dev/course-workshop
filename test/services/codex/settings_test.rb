require "test_helper"
require_relative "../../support/fake_codex_protocol"

class CodexSettingsTest < ActiveSupport::TestCase
  setup do
    @connection = FakeCodexProtocol.new
    @connection.models << { "model" => "test-model", "displayName" => "Test model",
      "supportedReasoningEfforts" => [ { "reasoningEffort" => "medium" } ], "defaultReasoningEffort" => "medium" }
    AiSetting.current.update!(model: "test-model", model_label: "Test model", style_instructions: "Use familiar examples")
  end

  test "a resumed tutor changes model and style with the accepted message" do
    conversation = lessons(:pitch).conversations.create!(browser_key: SecureRandom.hex(32), runtime_thread_id: "existing-thread")
    exchange = conversation.ask!(question: "Continue", locale: "en", request_key: SecureRandom.uuid)
    AiSetting.current.update!(style_instructions: "A later preference")
    Codex::Tutor.new(connection: @connection).reply(exchange, on_thread: ->(_) { }, cancelled: -> { false })
    params = @connection.calls.assoc("thread/resume").last
    assert_equal "test-model", params[:model]
    assert_equal "existing-thread", params[:threadId]
    assert_includes params[:developerInstructions], "replaces all style"
    input = JSON.parse(@connection.calls.assoc("turn/start").last[:input].first[:text])
    assert_equal "Use familiar examples", input.fetch("response_style")
    assert_equal "medium", @connection.calls.assoc("turn/start").last[:effort]
    assert_equal false, params[:config]["features.shell_tool"]
  end

  test "generation and images receive the saved model and style" do
    generation = CourseGeneration.submit!(topic: "Patterns", language: "en", request_key: SecureRandom.uuid)
    Codex::CourseGenerator.new(connection: @connection).generate(generation, token: "test", cancelled: -> { false })
    params = @connection.calls.assoc("thread/start").last
    assert_equal "test-model", params[:model]
    assert_equal "Use familiar examples", JSON.parse(@connection.calls.assoc("turn/start").last[:input].first[:text]).fetch("response_style")
    image = FakeCodexProtocol.new
    image.models = @connection.models
    bytes = Base64.strict_encode64(File.binread(Rails.root.join("db/seeds/images/commute-times.png")))
    events = [
      { "method" => "item/completed", "params" => { "threadId" => "thread-1", "turnId" => "turn-1", "item" => { "type" => "imageGeneration", "status" => "completed", "result" => bytes } } },
      { "method" => "turn/completed", "params" => { "threadId" => "thread-1", "turn" => { "id" => "turn-1", "status" => "completed" } } }
    ]
    image.define_singleton_method(:notification) { events.shift }
    AiSetting.current.update!(model: LocalAi::DEFAULT_MODEL, model_label: "Default", style_instructions: "New style")
    Codex::CoverGenerator.new(connection: image).generate(generation.course, cancelled: -> { false })
    params = image.calls.assoc("thread/start").last
    assert_equal "test-model", params[:model]
    assert_equal "Use familiar examples", JSON.parse(image.calls.assoc("turn/start").last[:input].first[:text]).fetch("response_style")
  end

  test "clearing style sends an explicit reset on an existing conversation" do
    AiSetting.current.update!(style_instructions: "")
    conversation = lessons(:pitch).conversations.create!(browser_key: SecureRandom.hex(32), runtime_thread_id: "existing-thread")
    exchange = conversation.ask!(question: "Continue", locale: "en", request_key: SecureRandom.uuid)
    Codex::Tutor.new(connection: @connection).reply(exchange, on_thread: ->(_) { }, cancelled: -> { false })
    assert_equal "", JSON.parse(@connection.calls.assoc("turn/start").last[:input].first[:text]).fetch("response_style")
    assert_includes @connection.calls.assoc("thread/resume").last[:developerInstructions], "empty string resets"
  end

  test "an unavailable selected model fails without silently using the default" do
    exchange = lessons(:pitch).conversations.create!(browser_key: SecureRandom.hex(32)).ask!(question: "Explain", locale: "en", request_key: SecureRandom.uuid)
    @connection.models.reject! { |model| model["model"] == "test-model" }
    error = assert_raises(LocalAi::Error) { Codex::Tutor.new(connection: @connection).reply(exchange, on_thread: ->(_) { }, cancelled: -> { false }) }
    assert_equal "model_unavailable", error.code
    assert_nil @connection.calls.assoc("thread/start")
  end

  test "the catalog follows pagination and excludes hidden or non text models" do
    @connection.models << { "model" => "hidden-model", "hidden" => true }
    @connection.models << { "model" => "image-only", "inputModalities" => [ "image" ] }
    original_rpc = @connection.method(:rpc)
    @connection.define_singleton_method(:rpc) do |method, **params|
      result = original_rpc.call(method, **params)
      next result unless method == "model/list"
      params[:cursor] ? { "data" => [ { "model" => "next-page" } ] } : result.merge("nextCursor" => "page-2")
    end
    result = Codex::ModelCatalog.new(connection: @connection).models
    assert_equal [ LocalAi::DEFAULT_MODEL, "test-model", "next-page" ].sort, result.map { |model| model["id"] }.sort
    assert_nil @connection.calls.assoc("thread/start")
  end
end
