require "application_system_test_case"

class DemoSystemTest < ApplicationSystemTestCase
  setup do
    @previous_demo = Rails.configuration.x.demo_mode
    Rails.configuration.x.demo_mode = true
    DemoCatalog.prepare!
  end

  teardown { Rails.configuration.x.demo_mode = @previous_demo }

  test "both courses show real media math highlighted code diagrams and working exercises" do
    %w[pl en].each do |language|
      course = Course.find_by!(slug: DemoMode::COURSE_SLUGS.find { |slug| slug.end_with?(language == "pl" ? "kawie" : "coffee") })
      visit localized_root_path(locale: language)
      assert_selector "[data-course-card]", count: 2
      assert_selector "[data-course-card] img" do |image|
        image.evaluate_script("this.complete && this.naturalWidth > 0")
      end
      find("[data-course-card] a[aria-label='#{course.title}']").click
      assert_selector "h1", text: course.title
      click_link course.lessons.first.title
      course.lessons.each.with_index(1) do |lesson, number|
        assert_selector "h1", text: lesson.title
        case number
        when 1, 3
          assert_selector ".lesson-content img" do |image|
            image.evaluate_script("this.complete && this.naturalWidth > 0")
          end
          assert_selector ".lesson-content table"
        when 2
          assert_selector ".lesson-block-output .katex", wait: 15
          assert_selector ".lesson-code span"
        when 4
          assert_selector ".lesson-block-output svg", wait: 15
          assert_selector ".lesson-code span"
        end
        find(".lesson-exercise summary").send_keys(:space)
        assert_selector ".lesson-exercise-answer[open]"
        assert_no_selector ".lesson-block-error"
        find("#lesson-completion-toggle").click
        assert_selector "#lesson-completion-toggle", text: language == "pl" ? "Cofnij ukończenie" : "Mark as incomplete"
        click_link(language == "pl" ? "Następna lekcja" : "Next lesson") if number < 4
      end
      visit course_path(course, locale: language)
      assert_selector "[data-controller=demo-chat]"
      find("[data-demo-chat-target=launcher]").click
      assert_selector "#demo-chat-panel[open]"
      assert_field "demo-chat-question", disabled: true
      assert_no_selector "[data-controller=conversation]"
      find("[data-demo-chat-target=closeButton]").send_keys(:escape)
      assert_no_selector "#demo-chat-panel[open]"
      assert_selector "[data-demo-chat-target=launcher]:focus"
    end
  end

  test "disabled previews remain readable at phone width and doubled text scale" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 320, height: 740, deviceScaleFactor: 1, mobile: false)
    %i[pl en].each do |language|
      visit new_generation_path(locale: language)
      assert_field "course_generation_topic", disabled: true
      assert_no_selector "#recent-heading"
      assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
      visit settings_path(locale: language)
      assert_field "ai_setting_style_instructions", disabled: true
      assert_selector "fieldset[disabled] select", count: 2
      assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
      page.execute_script("document.documentElement.style.fontSize = '200%'")
      assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
      page.save_screenshot(Rails.root.join("tmp/screenshots/demo-settings-#{language}.png"))
    end
    visit localized_root_path(locale: :en)
    page.save_screenshot(Rails.root.join("tmp/screenshots/demo-library-mobile.png"))
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
