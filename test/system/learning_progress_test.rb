require "application_system_test_case"

class LearningProgressSystemTest < ApplicationSystemTestCase
  test "completion and undo keep the reading position, exercise and assistant intact" do
    previous_ai = Rails.configuration.x.local_ai.enabled
    Rails.configuration.x.local_ai.enabled = true
    Rails.application.load_seed
    course = Course.find_by!(slug: "statystyka-na-co-dzien")
    visit course_lesson_path(course, course.lessons.second, locale: :pl)
    assert_selector ".lesson-block-output svg", wait: 15
    find("summary", text: "Porównaj swoją odpowiedź").click
    click_button "Otwórz asystenta kursu"
    fill_in "Twoje pytanie", with: "Zachowaj moje niewysłane pytanie"
    button = find_button("Oznacz jako ukończoną")
    button.execute_script("this.scrollIntoView({ block: 'center' }); this.focus({ preventScroll: true })")
    position = page.evaluate_script("scrollY")
    assert_operator position, :>, 100
    page.execute_script(<<~JS)
      window.progressReview = {
        article: document.querySelector('.lesson-content'),
        diagram: document.querySelector('.lesson-block-output svg'),
        panel: document.querySelector('dialog'),
        visits: 0
      };
      document.addEventListener('turbo:load', () => window.progressReview.visits++);
    JS

    [ [ "Cofnij ukończenie", 1, "btn-primary" ], [ "Oznacz jako ukończoną", 0, "btn-ghost" ] ].each do |label, count, next_style|
      find("#lesson-completion-toggle").send_keys(:enter)
      assert_button label, disabled: false
      assert_selector "#lesson-completion-toggle:focus", text: label
      assert_text "Ukończone lekcje: #{count} z 3"
      assert_selector "#lesson-navigation a[rel=next].#{next_style}"
      assert_in_delta position, page.evaluate_script("scrollY"), 2
      assert_selector ".lesson-exercise-answer[open]"
      assert_selector "dialog[open]"
      assert_field "Twoje pytanie", with: "Zachowaj moje niewysłane pytanie"
      assert page.evaluate_script(<<~JS)
        progressReview.visits === 0 &&
          progressReview.article === document.querySelector('.lesson-content') &&
          progressReview.diagram === document.querySelector('.lesson-block-output svg') &&
          progressReview.panel === document.querySelector('dialog')
      JS
    end
  ensure
    Rails.configuration.x.local_ai.enabled = previous_ai
  end

  test "complete, resume, review and undo with fresh counts after Turbo back navigation" do
    visit localized_root_path(locale: :pl)
    click_link courses(:listening).title
    click_link "Zacznij od pierwszej lekcji"
    assert_selector "h1", text: "Pitch"
    find_button("Oznacz jako ukończoną").send_keys(:enter)
    assert_text "Ta lekcja jest oznaczona jako ukończona."
    assert_text "Ukończone lekcje: 1 z 2"
    click_link "Biblioteka", exact: true
    click_link "Wznów kurs"
    assert_selector "h1", text: "Rhythm"
    switch_interface_language("English")
    click_button "Mark complete"
    assert_text "Course completed"
    click_link "Library", exact: true
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
    find("summary", text: "Plan kursu").click
    click_button "Oznacz jako ukończoną"
    assert_text "Ta lekcja jest oznaczona jako ukończona."
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    assert_selector "details[open] summary", text: "Plan kursu"
    assert_text "Ukończone lekcje: 1 z 2"
    assert_selector "details a[aria-current=page]", text: "Ukończona"
    click_link "Biblioteka", exact: true
    assert_link "Wznów kurs"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
