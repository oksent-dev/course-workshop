require "application_system_test_case"

class LessonMaterialsTest < ApplicationSystemTestCase
  test "the seeded lesson renders a stored image after reloading and navigating with Turbo" do
    Rails.application.load_seed
    course = Course.find_by!(slug: "statystyka-na-co-dzien")
    visit course_lesson_path(course, course.lessons.first, locale: :pl)
    assert_selector ".lesson-content h2", text: "Mierz to samo"
    assert_selector "figure img[alt*='Wykres słupkowy']"
    image = find("figure img")
    image.scroll_to(:center)
    assert_loaded_image
    page.refresh
    find("figure img").scroll_to(:center)
    assert_loaded_image

    click_link "Następna lekcja"
    assert_selector ".lesson-content pre code", text: "commute_times"
    click_link "Poprzednia lekcja"
    find("figure img").scroll_to(:center)
    assert_loaded_image

    page.execute_script("document.querySelector('figure img').src = '/missing-lesson-image.png'")
    assert_selector ".lesson-image-unavailable", text: "Obraz niedostępny: Wykres słupkowy"
    assert_no_selector "figure img"
  end

  test "wide code scrolls inside a keyboard-accessible region at phone width" do
    lesson = lessons(:pitch)
    lesson.update!(body: "```ruby\nputs \"#{"a" * 180}\"\n```")
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 320, height: 740, deviceScaleFactor: 1, mobile: false)
    visit course_lesson_path(lesson.course, lesson, locale: :en)
    code = find(".lesson-scroll")
    assert_equal "0", code["tabindex"]
    assert_equal "Code sample", code["aria-label"]
    assert page.evaluate_script("document.querySelector('.lesson-scroll').scrollWidth > document.querySelector('.lesson-scroll').clientWidth")
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    code.send_keys(:arrow_right)
    assert page.evaluate_script("document.activeElement.classList.contains('lesson-scroll')")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private

  def assert_loaded_image
    assert_selector "figure img:not(.hidden)" do
      page.evaluate_script("document.querySelector('figure img').complete && document.querySelector('figure img').naturalWidth > 0")
    end
  end
end
