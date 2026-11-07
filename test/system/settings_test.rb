require "application_system_test_case"
require_relative "../support/fake_model_catalog"

class SettingsSystemTest < ApplicationSystemTestCase
  setup do
    @ai, @authoring = Rails.configuration.x.local_ai, Rails.configuration.x.local_authoring
    @previous = [ @ai.enabled, @ai.model_catalog, @authoring.enabled ]
    @ai.enabled = @authoring.enabled = true
    @ai.model_catalog = FakeModelCatalog.new
  end

  teardown { @ai.enabled, @ai.model_catalog, @authoring.enabled = @previous }

  test "settings are to the right of language and persist across locale changes" do
    visit localized_root_path(locale: :pl)
    assert page.evaluate_script("document.querySelector('[aria-label=Ustawienia]').getBoundingClientRect().left > document.querySelector('[data-language-menu-target=trigger]').getBoundingClientRect().left")
    click_link "Ustawienia"
    assert_selector "h1", text: "Ustawienia"
    assert_selector "[data-site-header] a[aria-current=page][aria-label=Ustawienia]"
    assert_field "Źródło AI", with: "Codex", readonly: true
    select "Test model", from: "Model AI"
    assert_select "Poziom rozumowania", options: [ "Średni", "Wysoki" ], selected: "Średni"
    select "Wysoki", from: "Poziom rozumowania"
    select "GPT-6.1 Sol (domyślny)", from: "Model AI"
    assert_select "Poziom rozumowania", options: [ "Niski", "Średni", "Wysoki" ], selected: "Wysoki"
    fill_in "Instrukcja tonu i stylu", with: "Use short explanations and concrete examples."
    click_button "Zapisz ustawienia"
    assert_text "Ustawienia zapisane"
    switch_interface_language("English")
    assert_selector "h1", text: "Settings"
    assert_select "AI model", selected: "GPT-6.1 Sol (default)"
    assert_select "Reasoning level", selected: "High"
    assert_no_link "Reload model list"
    assert_field "Tone and style instruction", with: "Use short explanations and concrete examples."
    assert_no_selector "[data-primary-navigation] a[aria-current]"
  end

  test "mobile settings retain accessible controls and an unavailable catalog can recover" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 800, deviceScaleFactor: 1, mobile: false)
    @ai.model_catalog.unavailable = true
    visit settings_path(locale: :en)
    assert_text "The model list could not be loaded"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    fill_in "Tone and style instruction", with: "Be concise"
    click_button "Save settings"
    assert_text "Settings saved"
    @ai.model_catalog.unavailable = false
    visit settings_path(locale: :en)
    assert_select "AI model", with_options: [ "Test model" ]
    assert_field "Tone and style instruction", with: "Be concise"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "a model with fixed reasoning clears the selection and permits saving" do
    visit settings_path(locale: :en)
    select "Fixed reasoning model", from: "AI model"
    assert_select "Reasoning level", options: [ "Not configurable for this model" ], disabled: true
    click_button "Save settings"
    assert_text "Settings saved"
    assert_nil AiSetting.current.reasoning_effort
    select "Test model", from: "AI model"
    assert_select "Reasoning level", options: [ "Medium", "High" ], selected: "Medium", disabled: false
  end
end
