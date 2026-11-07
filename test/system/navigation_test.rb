require "application_system_test_case"

class NavigationTest < ApplicationSystemTestCase
  setup do
    @previous_authoring = Rails.configuration.x.local_authoring.enabled
    @previous_ai = Rails.configuration.x.local_ai.enabled
    Rails.configuration.x.local_authoring.enabled = true
    Rails.configuration.x.local_ai.enabled = true
  end

  teardown do
    Rails.configuration.x.local_authoring.enabled = @previous_authoring
    Rails.configuration.x.local_ai.enabled = @previous_ai
  end

  test "visitors can skip to the library and change its language with a keyboard" do
    visit "/pl"

    assert_selector "html[lang=pl]"
    assert_selector "h1", text: "Twoja biblioteka kursów"

    page.send_keys :tab
    assert_selector "a:focus", text: "Przejdź do treści"
    page.send_keys :enter
    assert_selector "main:focus"

    assert_no_link "English"
    find("[data-language-menu-target=trigger]").send_keys :enter
    assert_link "English"
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_link "English"
    assert_selector "summary:focus"
    find("[data-language-menu-target=trigger]").send_keys :enter
    page.driver.browser.action.send_keys(:tab, :tab).perform
    assert_selector "a:focus", text: "English"
    page.driver.browser.action.send_keys(:enter).perform
    assert_current_path "/en"
    assert_selector "html[lang=en]"
    assert_selector "h1", text: "Your course library"
    assert_selector "[data-primary-navigation] a[aria-current='page']", text: "Library"
    assert_selector "summary", text: "EN"

    find("[data-language-menu-target=trigger]").send_keys :enter
    page.driver.browser.action.send_keys(:tab).perform
    assert_selector "a:focus", text: "Polski"
    page.driver.browser.action.send_keys(:enter).perform
    assert_current_path "/pl"
    assert_selector "h1", text: "Twoja biblioteka kursów"
    assert_selector "[data-primary-navigation] a[aria-current='page']", text: "Biblioteka"
    assert_selector "summary", text: "PL"
  end

  test "shared navigation shows the active section and stays usable on a narrow screen" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 780, deviceScaleFactor: 1, mobile: false)
    visit localized_root_path(locale: :pl)
    click_link "Szkice", exact: true
    assert_selector "h1", text: "Szkice kursów"
    assert_selector "[data-primary-navigation] a[aria-current=page]", text: "Szkice"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    within("[data-site-header]") { click_link "Utwórz kurs" }
    assert_selector "h1", text: "Utwórz kurs"
    assert_selector "[data-site-header] a[aria-current=page]", text: "Utwórz kurs"
    assert_no_selector "[data-primary-navigation] a[aria-current]"
    find("[data-language-menu-target=trigger]").click
    find("h1").click
    assert_no_link "English"
    switch_interface_language("English")
    assert_current_path new_generation_path(locale: :en)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    click_link "Library", exact: true
    click_link courses(:listening).title
    assert_selector "[data-primary-navigation] a[aria-current=page]", text: "Library"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
