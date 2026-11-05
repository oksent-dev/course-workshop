require "application_system_test_case"

class NavigationTest < ApplicationSystemTestCase
  test "visitors can change the interface language" do
    visit "/pl"

    assert_selector "html[lang=pl]"
    assert_text "Buduj zrozumienie."

    click_link "English"
    assert_current_path "/en"
    assert_selector "html[lang=en]"
    assert_text "Build understanding."

    click_link "Polski"
    assert_current_path "/pl"
    assert_text "Buduj zrozumienie."
  end
end
