require "application_system_test_case"
require_relative "../support/conversation_history"

class ConversationHistorySystemTest < ApplicationSystemTestCase
  include ConversationHistory

  setup do
    @ai = Rails.configuration.x.local_ai
    @previous_enabled = @ai.enabled
    @ai.enabled = true
    @progress = Rails.configuration.x.learning_progress
    @previous_profile = @progress.local_profile
    @progress.local_profile = true
    @course = courses(:listening)
    learner = LearnerProfile.find_or_create_by!(key: "local")
    @conversation = Conversation.for_course!(course: @course, learner: learner)
    @exchanges = saved_exchanges(@conversation, 45)
    visit course_path(@course, locale: :en)
    click_button "Open course assistant"
    assert_selector "[data-exchange-id]", count: 20
    assert_at_latest
  end

  teardown do
    @ai.enabled = @previous_enabled
    @progress.local_profile = @previous_profile
  end

  test "reopening unchanged history and reloading both show the latest exchange" do
    page.execute_script("document.querySelector('[data-conversation-target=scroll]').scrollTop -= 400")
    click_button "Close conversation"
    click_button "Open course assistant"
    assert_at_latest
    page.execute_script("document.querySelector('[data-conversation-target=scroll]').scrollTop -= 400")
    page.refresh
    assert_selector "dialog[open]"
    assert_selector "[data-exchange-id]", count: 20
    assert_at_latest
    assert_text "Saved question 45"
  end

  test "scrolling loads older pages without moving the visible passage or losing it on polls and navigation" do
    scroll_to_oldest
    assert_selector "[data-exchange-id]", count: 40
    assert_anchor_unchanged
    assert_selector "[data-exchange-id='#{@exchanges[5].id}']"

    newest = saved_exchanges(@conversation, 1).first
    assert_selector "[data-exchange-id='#{newest.id}']", wait: 5
    assert_anchor_unchanged
    click_link "Start the first lesson"
    assert_selector "[data-conversation-target=contextLabel]", text: "Pitch"
    assert_selector "[data-exchange-id]", count: 41
    assert_anchor_unchanged

    scroll_to_oldest
    assert_selector "[data-exchange-id]", count: 46
    assert_anchor_unchanged
    assert_no_button "Load older messages"
    assert_equal 46, page.all("[data-exchange-id]").map { |item| item["data-exchange-id"] }.uniq.size
  end

  test "older history can be retried with the keyboard after a connection failure" do
    page.execute_script(<<~JS)
      const original = window.fetch;
      window.fetch = (...args) => {
        if (new URL(args[0], location.href).searchParams.has('before')) {
          window.fetch = original;
          return Promise.reject(new Error('Offline'));
        }
        return original(...args);
      };
    JS
    scroll_to_oldest
    assert_text "Could not load older messages"
    assert_selector "[data-exchange-id]", count: 20
    assert_button "Load older messages", disabled: false
    find_button("Load older messages").send_keys(:enter)
    assert_selector "[data-exchange-id]", count: 40
    assert_no_text "Could not load older messages"
    assert_selector "[data-exchange-id='#{@exchanges.last.id}']"
    assert_field "Your question", disabled: false
  end

  test "Polish history controls fit a narrow viewport and expanded conversation" do
    click_button "Close conversation"
    assert_no_selector "dialog[open]"
    switch_interface_language("Polski")
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 740, deviceScaleFactor: 1, mobile: false)
    click_button "Otwórz asystenta kursu"
    assert_selector "[data-exchange-id]", count: 20
    assert_at_latest
    click_button "Powiększ rozmowę"
    scroll_to_oldest
    assert_selector "[data-exchange-id]", count: 40
    button = find_button("Wczytaj starsze wiadomości")
    button.send_keys(:tab)
    assert_operator button.native.rect.width, :<=, 296
    assert_operator button.native.rect.height, :>=, 44
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.execute_script("document.querySelector('[data-conversation-target=scroll]').scrollTop = 0")
    assert_selector "[data-exchange-id]", count: 45
    page.save_screenshot(Rails.root.join("tmp/screenshots/conversation-history-mobile.png"))
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private

  def assert_at_latest
    assert_selector "[data-conversation-target=scroll][aria-busy=false]"
    distance = page.evaluate_script(<<~JS)
      (() => {
        const scroll = document.querySelector('[data-conversation-target=scroll]');
        return scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight;
      })()
    JS
    assert_operator distance, :<=, 8
  end

  def scroll_to_oldest
    page.execute_script(<<~JS)
      const scroll = document.querySelector('[data-conversation-target=scroll]');
      scroll.scrollTop = 0;
      const first = document.querySelector('[data-exchange-id]');
      window.historyAnchor = { id: first.dataset.exchangeId, offset: first.getBoundingClientRect().top - scroll.getBoundingClientRect().top };
    JS
  end

  def assert_anchor_unchanged
    page.driver.browser.execute_async_script("requestAnimationFrame(arguments[0])")
    delta = page.evaluate_script(<<~JS)
      (() => {
        const scroll = document.querySelector('[data-conversation-target=scroll]');
        const item = document.querySelector(`[data-exchange-id="${window.historyAnchor.id}"]`);
        return item.getBoundingClientRect().top - scroll.getBoundingClientRect().top - window.historyAnchor.offset;
      })()
    JS
    assert_in_delta 0, delta, 2
  end
end
