require "application_system_test_case"

class CodeHighlightingTest < ApplicationSystemTestCase
  test "highlighting survives Turbo and language changes, and code scrolls with the keyboard" do
    first = lessons(:pitch)
    second = first.course.lessons.where.not(id: first.id).first
    source = "class Course < ApplicationRecord\n  TITLE = \"#{'A long course title ' * 8}\"\nend\n"
    first.update!(body: "```ruby\n#{source}```")
    second.update!(body: "```sql\nSELECT title FROM courses;\n```")
    visit course_lesson_path(first.course, first, locale: :en)
    assert_selector ".lesson-code .k", text: "class"
    assert_equal source, find("pre code").evaluate_script("this.textContent")
    keyword_color = find(".lesson-code .k", text: "class").style("color")["color"]
    assert_not_equal find("pre code").style("color")["color"], keyword_color
    page.execute_script("window.highlightNavigationCheck = true")
    click_link "Next lesson"
    assert_selector "h1", text: second.title
    assert_selector ".lesson-code span", text: "SELECT"
    click_link "Previous lesson"
    assert_selector "h1", text: first.title
    assert_selector ".lesson-code .k", text: "class"
    assert page.evaluate_script("window.highlightNavigationCheck")
    click_link "Polski"
    assert_selector ".lesson-scroll[aria-label='Przykład kodu'] .lesson-code .k", text: "class"
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 740, deviceScaleFactor: 1, mobile: false)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    scroll_region = find(".lesson-scroll", text: "class Course")
    scroll_region.send_keys(:arrow_right)
    assert_selector ".lesson-scroll:focus"
    assert_operator scroll_region.evaluate_script("this.scrollWidth"), :>, scroll_region.evaluate_script("this.clientWidth")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
