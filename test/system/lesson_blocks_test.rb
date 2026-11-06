require "application_system_test_case"

class LessonBlocksSystemTest < ApplicationSystemTestCase
  test "read math and a diagram, reveal an answer with the keyboard, and navigate with Turbo" do
    Rails.application.load_seed
    course = Course.find_by!(slug: "statystyka-na-co-dzien")
    visit course_lesson_path(course, course.lessons.second, locale: :pl)
    assert_selector ".lesson-block-output .katex", count: 1, wait: 15
    assert_selector ".lesson-block-output svg", count: 1, wait: 15
    assert_selector ".lesson-block-output math"
    assert_no_text "Suma wzrosła do 60 minut"
    summary = find("summary", text: "Porównaj swoją odpowiedź")
    summary.send_keys(:space)
    assert_selector ".lesson-exercise-answer[open]"
    assert_text "Suma wzrosła do 60 minut"
    summary.send_keys(:space)
    assert_no_text "Suma wzrosła do 60 minut"

    page.execute_script("window.lessonNavigationCheck = true")
    click_link "Następna lekcja"
    assert_selector "h1", text: course.lessons.third.title
    click_link "Poprzednia lekcja"
    assert_selector "h1", text: course.lessons.second.title
    assert page.evaluate_script("window.lessonNavigationCheck")
    assert_selector ".lesson-block-output .katex", count: 1, wait: 15
    assert_selector ".lesson-block-output svg", count: 1, wait: 15

    click_link "English"
    assert_selector ".lesson-exercise summary", text: "Compare your answer"
    assert_selector ".lesson-block-output svg", count: 1, wait: 15
    assert_selector ".lesson-block-output .katex", count: 1
    assert_no_selector ".lesson-diagram-sandbox"
  end

  test "a bad formula and rejected script leave the rest of the lesson usable" do
    lesson = lessons(:pitch)
    lesson.update!(body: <<~MARKDOWN)
      \`\`\`math
      \\notARealCommand{1}
      \`\`\`

      \`\`\`mermaid
      flowchart TD
      accDescr: An invalid chart.
      A["<script>window.blockScriptRan = true</script>"]
      \`\`\`

      \`\`\`math
      \\frac{1}{2}
      \`\`\`

      Still readable.
    MARKDOWN
    visit course_lesson_path(lesson.course, lesson, locale: :en)
    assert_text "This block could not be displayed.", wait: 15
    assert_selector ".lesson-block-error"
    assert_selector ".lesson-block-output .katex", count: 1
    assert_text "Still readable."
    assert_nil page.evaluate_script("window.blockScriptRan")
    assert_no_selector ".lesson-content script, .lesson-content iframe, .lesson-content a[href^='javascript:']"
  end

  test "learning blocks remain inside the page at a narrow phone width" do
    Rails.application.load_seed
    course = Course.find_by!(slug: "statystyka-na-co-dzien")
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 320, height: 740, deviceScaleFactor: 1, mobile: false)
    visit course_lesson_path(course, course.lessons.second, locale: :pl)
    assert_selector ".lesson-block-output svg", wait: 15
    assert_selector ".lesson-block-output .katex"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    find("summary", text: "Porównaj swoją odpowiedź").click
    assert_text "Suma wzrosła do 60 minut"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
