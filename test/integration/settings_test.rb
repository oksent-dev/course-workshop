require "test_helper"
require_relative "../support/fake_model_catalog"

class SettingsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @ai = Rails.configuration.x.local_ai
    @previous = [ @ai.enabled, @ai.model_catalog ]
    @ai.enabled = true
    @ai.model_catalog = @catalog = FakeModelCatalog.new
    @local = { "REMOTE_ADDR" => "127.0.0.1" }
  end

  teardown { @ai.enabled, @ai.model_catalog = @previous }

  test "settings persist globally with a fixed source and an account model" do
    get settings_path(locale: :en), headers: @local
    assert_response :success
    assert_select "input[readonly][value=Codex]"
    assert_select "option[selected][value=?]", LocalAi::DEFAULT_MODEL
    assert_select "a[aria-current=page][href=?]", settings_path(locale: :en)
    save_settings(model: "test-model", style_instructions: " Use concrete examples. ", provider: "arbitrary")
    assert_redirected_to settings_path(locale: :en)
    assert_equal "codex", AiSetting.current.snapshot["provider"]
    assert_equal "Test model", AiSetting.current.model_label
    assert_equal "Use concrete examples.", AiSetting.current.style_instructions
    get settings_path(locale: :pl), headers: @local
    assert_select "option[selected][value=test-model]"
    assert_select "textarea", "Use concrete examples."
  end

  test "unavailable and forged models cannot replace saved settings" do
    save_settings(model: "invented-model", style_instructions: "Keep this draft")
    assert_response :unprocessable_content
    assert_equal LocalAi::DEFAULT_MODEL, AiSetting.current.model
    assert_select "textarea", "Keep this draft"
    @catalog.unavailable = true
    save_settings(model: "test-model")
    assert_response :unprocessable_content
    save_settings(style_instructions: "Still editable offline")
    assert_response :see_other
    assert_equal "Still editable offline", AiSetting.current.style_instructions
    get settings_path(locale: :en), headers: @local
    assert_select "[role=status]", /model list could not be loaded/
  end

  test "style is bounded escaped and removable" do
    save_settings(style_instructions: "a" * 1001)
    assert_response :unprocessable_content
    assert_equal "", AiSetting.current.style_instructions
    save_settings(style_instructions: "<script>alert('style')</script>")
    follow_redirect!
    assert_select "textarea", "<script>alert('style')</script>"
    assert_select "script", text: "alert('style')", count: 0
    save_settings(style_instructions: "")
    assert_equal "", AiSetting.current.style_instructions
  end

  test "a stale tab cannot silently overwrite another save" do
    version = AiSetting.current.lock_version
    save_settings(style_instructions: "First choice", lock_version: version)
    save_settings(style_instructions: "Stale choice", lock_version: version)
    assert_response :conflict
    assert_equal "First choice", AiSetting.current.style_instructions
    assert_select "textarea", "Stale choice"
  end

  test "settings are inaccessible to remote disabled and production requests" do
    get settings_path(locale: :en), headers: { "REMOTE_ADDR" => "203.0.113.2" }
    assert_response :not_found
    patch settings_path(locale: :en), params: { ai_setting: { model: "test-model" } }, headers: { "REMOTE_ADDR" => "203.0.113.2" }
    assert_response :not_found
    @ai.enabled = false
    get settings_path(locale: :en), headers: @local
    assert_response :not_found
    @ai.enabled = true
    environment = Rails.env
    Rails.env = "production"
    get settings_path(locale: :en), headers: @local
    assert_response :not_found
  ensure
    Rails.env = environment if environment
  end

  test "course provenance stays historical on draft generation and published outlines" do
    save_settings(model: "test-model", style_instructions: "A private preference")
    authoring = Rails.configuration.x.local_authoring
    previous_authoring = authoring.enabled
    authoring.enabled = true
    generation = CourseGeneration.submit!(topic: "Patterns", language: "en", request_key: SecureRandom.uuid)
    course = generation.course
    save_settings(model: LocalAi::DEFAULT_MODEL)
    [ generation_path(generation, locale: :en), draft_path(course.id, locale: :en) ].each do |path|
      get path, headers: @local
      assert_response :success
      assert_select "[data-course-ai-model=test-model]", text: "Generation model: Test model · Codex"
      assert_not_includes response.body, "A private preference"
    end
    course.update!(status: :published)
    get course_path(course, locale: :en), headers: @local
    assert_select "[data-course-ai-model=test-model]"
  ensure
    authoring.enabled = previous_authoring if authoring
  end

  private

  def save_settings(**attributes)
    input = { model: AiSetting.current.model, style_instructions: AiSetting.current.style_instructions, lock_version: AiSetting.current.lock_version }.merge(attributes)
    patch settings_path(locale: :en), params: { ai_setting: input }, headers: @local
  end
end
