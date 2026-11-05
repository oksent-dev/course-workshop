require "application_system_test_case"

class NavigationTest < ApplicationSystemTestCase
  test "visitors can skip to the library and change its language with a keyboard" do
    visit "/pl"

    assert_selector "html[lang=pl]"
    assert_selector "h1", text: "Twoja biblioteka kursów"

    page.send_keys :tab
    assert_selector "a:focus", text: "Przejdź do treści"
    page.send_keys :enter
    assert_selector "main:focus"

    find_link("English").send_keys :enter
    assert_current_path "/en"
    assert_selector "html[lang=en]"
    assert_selector "h1", text: "Your course library"
    assert_selector "nav a[aria-current='page']", text: "English"

    find_link("Polski").send_keys :enter
    assert_current_path "/pl"
    assert_selector "h1", text: "Twoja biblioteka kursów"
    assert_selector "nav a[aria-current='page']", text: "Polski"
  end
end
