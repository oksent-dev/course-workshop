require "application_system_test_case"
require_relative "../support/fake_tutor"

class LessonConversationSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @settings = Rails.configuration.x.local_ai
    @previous_enabled, @previous_adapter = @settings.enabled, @settings.adapter
    @settings.enabled = true
    @settings.adapter = FakeTutor.new
  end

  teardown do
    @settings.enabled, @settings.adapter = @previous_enabled, @previous_adapter
  end

  test "ask, follow up, reopen the lesson, and switch interface language" do
    lesson = lessons(:pitch)
    visit course_lesson_path(lesson.course, lesson, locale: :en)
    click_button "Ask about this lesson"
    assert_text "Ask for an explanation"
    fill_in "Your question", with: "Explain pitch"
    click_button "Send question"
    assert_text "Waiting to start"
    perform_enqueued_jobs
    assert_text "A high note has a higher frequency."

    fill_in "Your question", with: "Give me another example"
    click_button "Send question"
    assert_text "Waiting to start"
    perform_enqueued_jobs
    assert_selector "p", text: "A high note has a higher frequency.", count: 2

    click_link "Polski"
    click_button "Zapytaj o tę lekcję"
    assert_text "Give me another example"
    assert_field "Twoje pytanie"
    assert_selector "h1", text: lesson.title
  end

  test "a cancelled queued reply and an unavailable runtime are understandable" do
    lesson = lessons(:pitch)
    visit course_lesson_path(lesson.course, lesson, locale: :en)
    click_button "Ask about this lesson"
    assert_text "Ask for an explanation"
    fill_in "Your question", with: "Explain pitch"
    click_button "Send question"
    assert_text "Waiting to start"
    click_button "Cancel reply"
    assert_text "Reply cancelled."

    @settings.adapter.error = "unavailable"
    fill_in "Your question", with: "Try again"
    click_button "Send question"
    assert_text "Waiting to start"
    perform_enqueued_jobs
    assert_text "The local tutor is unavailable."
    assert_button "Send question", disabled: false
  end

  test "quote highlighted code, keep a draft while reading, and save the passage with the answer" do
    lesson = lessons(:pitch)
    code = "puts \"<example>\"\n"
    lesson.update!(body: "A passage to explain.\n\n```ruby\n#{code}```")
    visit course_lesson_path(lesson.course, lesson, locale: :en)
    select_text(".lesson-content pre code")
    assert_button "Ask about this passage"
    page.execute_script("document.querySelector('.lesson-content p').style.paddingBottom = '40px'")
    expected_top = page.evaluate_script("window.getSelection().getRangeAt(0).getBoundingClientRect().bottom + 8")
    assert_selector ".lesson-selection-action" do |action|
      (action.style("top")["top"].to_f - expected_top).abs < 1
    end
    click_button "Ask about this passage"
    assert_selector "dialog[open]"
    assert_selector "textarea:focus"
    assert_selector "[data-conversation-target='quoteText']", text: code.strip
    fill_in "Your question", with: "Why these quotes?"
    position = page.evaluate_script("scrollY")
    find("textarea").send_keys(:escape)
    assert_no_selector "dialog[open]"
    assert_selector ".lesson-chat-launcher:focus"
    assert_equal position, page.evaluate_script("scrollY")
    click_button "Ask about this lesson"
    assert_field "Your question", with: "Why these quotes?"
    click_button "Remove"
    assert_no_selector "[data-conversation-target='quotePreview']"
    click_button "Close conversation"

    select_text(".lesson-content pre code")
    page.driver.browser.action.key_down(:alt).send_keys(:enter).key_up(:alt).perform
    assert_selector "dialog[open]"
    click_button "Send question"
    assert_text "Waiting to start"
    assert_no_selector "[data-conversation-target='quotePreview']"
    perform_enqueued_jobs
    assert_text "A high note has a higher frequency."
    assert_equal code.strip, Exchange.last.selected_text
    assert_equal code.strip, @settings.adapter.calls.last[:context]["selected_text"]
    within("[role='log']") { assert_selector "blockquote", text: code.strip }
    page.refresh
    click_button "Ask about this lesson"
    within("[role='log']") { assert_selector "blockquote", text: code.strip }
    assert_no_selector "[data-conversation-target='quotePreview']"
  end

  test "a failed request preserves the question and quote, and changing the quote gets a new request key" do
    lesson = lessons(:pitch)
    visit course_lesson_path(lesson.course, lesson, locale: :en)
    select_text(".lesson-content p")
    click_button "Ask about this passage"
    assert_button "Send question", disabled: false
    page.execute_script(<<~JS)
      const originalFetch = window.fetch;
      window.submissions = [];
      window.fetch = async (url, options = {}) => {
        if (options.method === "POST") {
          window.submissions.push(JSON.parse(options.body));
          if (window.submissions.length === 1) throw new TypeError("Offline");
        }
        return originalFetch(url, options);
      };
    JS
    fill_in "Your question", with: "Explain this"
    click_button "Send question"
    assert_text "The conversation could not be loaded."
    assert_field "Your question", with: "Explain this"
    assert_selector "[data-conversation-target='quoteText']", text: lesson.body
    click_button "Remove"
    click_button "Send question"
    assert_text "Waiting to start"
    assert_nil Exchange.last.selected_text
    keys = page.evaluate_script("window.submissions.map(item => item.request_key)")
    assert_equal 2, keys.uniq.size
  end

  test "the widget fits a phone, ignores outside selection, and resets on another lesson" do
    lesson = lessons(:pitch)
    lesson.update!(body: "A short passage.\n\n#{'Long text. ' * 220}")
    visit course_lesson_path(lesson.course, lesson, locale: :pl)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 740, deviceScaleFactor: 1, mobile: false)
    select_text("h1")
    assert_no_selector ".lesson-selection-action"
    select_text(".lesson-content p:last-child")
    assert_button "Zaznacz krótszy fragment (do 2000 znaków).", disabled: true
    select_text(".lesson-content p:first-child")
    click_button "Zapytaj o ten fragment"
    fill_in "Twoje pytanie", with: "A draft"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    assert page.evaluate_script("document.querySelector('dialog').getBoundingClientRect().bottom <= innerHeight")
    assert page.evaluate_script("document.querySelector('dialog').getBoundingClientRect().top >= 0")
    click_button "Zamknij rozmowę"
    click_link "Następna lekcja"
    assert_selector "h1", text: lessons(:rhythm).title
    click_button "Zapytaj o tę lekcję"
    assert_field "Twoje pytanie", with: ""
    assert_no_selector "[data-conversation-target='quotePreview']"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "the selection action waits for pointer release and the launcher gives its icon room" do
    lesson = lessons(:pitch)
    visit course_lesson_path(lesson.course, lesson, locale: :en)
    launcher = find(".lesson-chat-launcher")
    assert_equal 64, launcher.evaluate_script("this.getBoundingClientRect().width")
    assert_equal 64, launcher.evaluate_script("this.getBoundingClientRect().height")
    assert_equal 28, launcher.find("svg").evaluate_script("this.getBoundingClientRect().width")
    paragraph = find(".lesson-content p")
    width = paragraph.evaluate_script("this.getBoundingClientRect().width")
    page.driver.browser.action.move_to(paragraph.native, -width.to_i / 2 + 4, 0).click_and_hold.move_by(110, 0).perform
    assert_not_empty page.evaluate_script("window.getSelection().toString()")
    assert_no_selector ".lesson-selection-action"
    page.driver.browser.action.release.perform
    assert_button "Ask about this passage"
    click_button "Ask about this passage"
    assert_selector "dialog[open]"
  ensure
    page.driver.browser.action.release.perform
  end

  private

  def select_text(selector)
    element = find(selector)
    element.scroll_to(:center)
    page.execute_script(<<~JS, element)
      const range = document.createRange();
      range.selectNodeContents(arguments[0]);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    JS
  end
end
