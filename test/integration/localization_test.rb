require "test_helper"

class LocalizationTest < ActionDispatch::IntegrationTest
  test "the root redirects to the default language" do
    get "/"
    assert_redirected_to "/pl"
  end

  test "Polish and English pages render localized content and navigation" do
    { pl: "Warsztat Kursów", en: "Course Workshop" }.each do |locale, name|
      get localized_root_path(locale: locale)

      assert_response :success
      assert_select "html[lang=?]", locale.to_s
      assert_select "title", name
      assert_select "nav a[hreflang=pl][href='/pl'][aria-label='Polski']"
      assert_select "nav a[hreflang=en][href='/en'][aria-label='English']"
      assert_select "nav a[aria-current=page][hreflang=?]", locale.to_s
    end
  end

  test "a request does not leak its locale into the next request" do
    get "/en"
    assert_equal I18n.default_locale, I18n.locale

    get "/pl"
    assert_select "title", "Warsztat Kursów"
  end

  test "authoring navigation follows local access and the active generation section" do
    previous_authoring = Rails.configuration.x.local_authoring.enabled
    previous_ai = Rails.configuration.x.local_ai.enabled
    Rails.configuration.x.local_authoring.enabled = true
    Rails.configuration.x.local_ai.enabled = true
    host! "localhost"
    local = { "REMOTE_ADDR" => "127.0.0.1" }
    get new_generation_path(locale: :en), headers: local
    assert_select "[data-site-header] a[aria-current=page][href=?]", new_generation_path(locale: :en)
    assert_select "main a[href=?]", localized_root_path(locale: :en), count: 0
    generation = CourseGeneration.submit!(topic: "Music", language: "en", request_key: SecureRandom.uuid)
    get generation_path(generation, locale: :en), headers: local
    assert_select "[data-primary-navigation] a[aria-current=page][href=?]", drafts_path(locale: :en)
    get localized_root_path(locale: :en), headers: { "REMOTE_ADDR" => "203.0.113.1" }
    assert_select "[data-site-header] a[href=?]", drafts_path(locale: :en), count: 0
    assert_select "[data-site-header] a[href=?]", new_generation_path(locale: :en), count: 0
    Rails.configuration.x.local_authoring.enabled = false
    get localized_root_path(locale: :en), headers: local
    assert_select "[data-site-header] a[href=?]", drafts_path(locale: :en), count: 0
    assert_select "[data-site-header] a[href=?]", new_generation_path(locale: :en), count: 0
  ensure
    Rails.configuration.x.local_authoring.enabled = previous_authoring
    Rails.configuration.x.local_ai.enabled = previous_ai
  end

  test "unsupported locales return not found" do
    get "/de"
    assert_response :not_found
  end

  test "health checks do not require a locale" do
    get "/up"
    assert_response :success
  end
end
