require "application_system_test_case"

class LearningProgressSystemTest < ApplicationSystemTestCase
  test "complete, resume, review and undo with fresh counts after Turbo back navigation" do
    visit localized_root_path(locale: :pl)
    click_link courses(:listening).title
    click_link "Zacznij od pierwszej lekcji"
    assert_selector "h1", text: "Pitch"
    find_button("Oznacz jako ukończoną").send_keys(:enter)
    assert_text "Ta lekcja jest oznaczona jako ukończona."
    assert_text "Ukończone lekcje: 1 z 2"
    click_link "Twoja biblioteka kursów"
    click_link "Wznów kurs"
    assert_selector "h1", text: "Rhythm"
    click_link "English"
    click_button "Mark complete"
    assert_text "Course completed"
    click_link "Your course library"
    assert_text "2 of 2 lessons completed"
    click_link "Review course"
    assert_selector "h1", text: "Pitch"
    click_button "Mark as incomplete"
    assert_button "Mark complete"
    page.go_back
    assert_selector "h1", text: "Your course library"
    assert_text "1 of 2 lessons completed"
    click_link "Resume course"
    assert_selector "h1", text: "Pitch"
    assert_button "Mark complete"
    assert_equal 1, LessonProgress.where.not(completed_at: nil).count
  end

  test "completion controls and progress remain usable on a narrow screen" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 320, height: 740, deviceScaleFactor: 1, mobile: false)
    visit course_lesson_path(courses(:listening), lessons(:pitch), locale: :pl)
    click_button "Oznacz jako ukończoną"
    assert_text "Ta lekcja jest oznaczona jako ukończona."
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    find("summary", text: "Plan kursu").click
    assert_text "Ukończone lekcje: 1 z 2"
    assert_selector "details a[aria-current=page]", text: "Ukończona"
    click_link "Twoja biblioteka kursów"
    assert_link "Wznów kurs"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
