require "test_helper"

class AiConfigurationTest < ActiveSupport::TestCase
  test "a course and all its image stages retain the submission settings across retries" do
    settings = AiSetting.current
    settings.update!(model: "test-model", model_label: "Test model", reasoning_effort: "high", style_instructions: "Use short sentences")
    generation = CourseGeneration.submit!(topic: "Patterns", language: "en", request_key: SecureRandom.uuid)
    original = generation.ai_configuration.deep_dup
    settings.update!(model: LocalAi::DEFAULT_MODEL, reasoning_effort: "low", style_instructions: "A different style")
    assert_equal "high", original.fetch("reasoning_effort")
    generation.update!(status: :failed)
    generation.retry!(generation.attempt)
    assert_equal original, generation.reload.ai_configuration
    cover = generation.course.create_cover_generation!(expires_at: 7.minutes.from_now)
    assert_equal original, cover.ai_configuration
    assert_equal original, AiRun.start!(generation, "step", SecureRandom.uuid).ai_configuration
    assert_equal "test-model", generation.course.reload.generation_model
    assert_equal generation.id, CourseGeneration.submit!(topic: "Patterns", language: "en", request_key: generation.request_key).id
    assert_equal original, generation.reload.ai_configuration
  end

  test "new conversation messages use current settings while queued messages keep their snapshot" do
    conversation = lessons(:pitch).conversations.create!(browser_key: SecureRandom.hex(32))
    first = conversation.ask!(question: "Explain", locale: "en", request_key: SecureRandom.uuid)
    settings = AiSetting.current
    settings.update!(model: "test-model", model_label: "Test model", reasoning_effort: "high", style_instructions: "Be concise")
    assert_equal LocalAi::DEFAULT_MODEL, first.reload.ai_model
    assert_equal first.id, conversation.ask!(question: "Explain", locale: "en", request_key: first.request_key).id
    first.finish!(:completed, answer: "First answer")
    second = conversation.ask!(question: "Continue", locale: "en", request_key: SecureRandom.uuid)
    assert_equal "test-model", second.ai_model
    assert_equal "high", second.ai_configuration["reasoning_effort"]
    assert_equal "Be concise", second.ai_configuration["style_instructions"]
    assert_equal second.ai_configuration, AiRun.start!(second, "reply", SecureRandom.uuid).ai_configuration
  end

  test "replacement covers inherit the edit request rather than later settings" do
    course = courses(:listening)
    course.update!(status: :draft)
    conversation = course.conversations.create!(learner_profile: LearnerProfile.create!(key: SecureRandom.hex(32)), mode: "editor")
    exchange = conversation.ask!(question: "New cover", locale: "en", request_key: SecureRandom.uuid)
    AiSetting.current.update!(model: "test-model", model_label: "Test model", style_instructions: "Later preference")
    request = course.draft_cover_requests.create!(exchange: exchange, prompt: "A quiet landscape", expected_revision: course.revision)
    assert_equal exchange.ai_configuration, request.ai_configuration
    request.update!(status: :failed)
    exchange.finish!(:completed, answer: "Queued")
    assert_equal request.ai_configuration, request.retry!.ai_configuration
  end
end
