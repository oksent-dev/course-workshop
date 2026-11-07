require "application_system_test_case"

class CourseDraftsTest < ApplicationSystemTestCase
  setup do
    @previous_enabled = Rails.configuration.x.local_authoring.enabled
    Rails.configuration.x.local_authoring.enabled = true
    @course = Course.create!(category: categories(:music), slug: "review-draft", title: "Review draft", description: "A new course.", language: "en")
    @course.lessons.create!(position: 1, title: "First lesson", body: "A useful explanation.")
    @course.lessons.create!(position: 2, title: "Second lesson", body: "Practice it.")
  end

  teardown { Rails.configuration.x.local_authoring.enabled = @previous_enabled }

  test "review both lessons, switch language and explicitly approve the draft" do
    visit localized_root_path(locale: :pl)
    assert_no_link "Review draft"
    click_link "Szkice", exact: true
    click_link "Review draft"
    assert_text "Podgląd szkicu"
    click_link "2. Second lesson"
    assert_selector "article h2", text: "Second lesson"
    switch_interface_language("English")
    assert_selector "article h2", text: "Second lesson"
    assert_current_path draft_path(@course.id, locale: :en, lesson_id: @course.lessons.last.id)
    find_button("Approve and add to library").send_keys(:enter)
    assert_text "The course has been added to your library."
    click_link "Start the first lesson"
    assert_selector "h1", text: "First lesson"
    assert_button "Mark complete"
    assert @course.reload.published?
  end

  test "draft preview remains readable on a narrow screen" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 740, deviceScaleFactor: 1, mobile: false)
    visit draft_path(@course.id, locale: :pl)
    assert_button "Zatwierdź i dodaj do biblioteki"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    click_link "2. Second lesson"
    assert_selector "article h2", text: "Second lesson"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
