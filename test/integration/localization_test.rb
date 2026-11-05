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
      assert_select "nav a[hreflang=pl][href='/pl']", "Polski"
      assert_select "nav a[hreflang=en][href='/en']", "English"
      assert_select "nav a[aria-current=page][hreflang=?]", locale.to_s
    end
  end

  test "a request does not leak its locale into the next request" do
    get "/en"
    assert_equal I18n.default_locale, I18n.locale

    get "/pl"
    assert_select "title", "Warsztat Kursów"
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
