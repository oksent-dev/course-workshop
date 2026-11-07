require "application_system_test_case"
require_relative "../support/fake_tutor"

class CourseAssistantSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @ai = Rails.configuration.x.local_ai
    @authoring = Rails.configuration.x.local_authoring
    @previous = [ @ai.enabled, @ai.adapter, @authoring.enabled, @ai.editor ]
    @ai.enabled = @authoring.enabled = true
    @ai.adapter = @ai.editor = FakeTutor.new
    @course = courses(:listening)
  end

  teardown { @ai.enabled, @ai.adapter, @authoring.enabled, @ai.editor = @previous }

  test "one panel follows Turbo navigation and a running reply keeps its original lesson" do
    visit course_path(@course, locale: :en)
    click_button "Open course assistant"
    assert_text "Ask for an explanation"
    fill_in "Your question", with: "Keep this draft while reading"
    page.execute_script("window.originalPanel = document.querySelector('dialog')")
    click_link "Start the first lesson"
    assert_selector "[data-conversation-target=contextLabel]", text: "Pitch"
    assert_field "Your question", with: "Keep this draft while reading"
    assert page.evaluate_script("window.originalPanel === document.querySelector('dialog')")
    click_button "Send question"
    assert_text "Waiting to start"
    click_link "Next lesson"
    assert_selector "[data-conversation-target=contextLabel]", text: "Rhythm"
    assert_text "Waiting to start"
    perform_enqueued_jobs
    assert_text "A high note has a higher frequency."
    assert_equal lessons(:pitch).id, Exchange.last.lesson_context["lesson_id"]
    fill_in "Your question", with: "Now about rhythm"
    click_button "Send question"
    assert_text "Waiting to start"
    assert_equal lessons(:rhythm).id, Exchange.last.lesson_context["lesson_id"]
    click_button "Expand conversation"
    page.refresh
    assert_selector "dialog[open][data-expanded=true]"
    assert_text "Now about rhythm"
  end

  test "a quote survives navigation and language change without changing its source" do
    visit course_lesson_path(@course, lessons(:pitch), locale: :en)
    select_passage
    click_button "Ask about this passage"
    assert_text "Ask for an explanation"
    fill_in "Your question", with: "Which frequency?"
    click_link "Next lesson"
    assert_selector "[data-conversation-target=contextLabel]", text: "Rhythm"
    assert_selector "[data-conversation-target=quoteSource]", text: "Pitch"
    switch_interface_language("Polski")
    assert_selector "dialog[open]"
    assert_field "Twoje pytanie", with: "Which frequency?"
    click_button "Wyślij pytanie"
    assert_text "Oczekiwanie na rozpoczęcie"
    assert_equal lessons(:pitch).id, Exchange.last.lesson_context["lesson_id"]
    assert_equal lessons(:pitch).body, Exchange.last.selected_text
    assert_equal "pl", Exchange.last.locale
  end

  test "tabs share saved history but preserve independent composers and course state" do
    visit course_path(@course, locale: :en)
    first = current_window
    click_button "Open course assistant"
    assert_text "Ask for an explanation"
    fill_in "Your question", with: "First tab draft"
    second = open_new_window
    within_window second do
      visit course_path(@course, locale: :en)
      click_button "Open course assistant" unless page.has_selector?("dialog[open]", wait: 0)
      fill_in "Your question", with: "Question from second tab"
      click_button "Send question"
      assert_text "Waiting to start"
      perform_enqueued_jobs
      assert_text "A high note has a higher frequency."
    end
    within_window first do
      assert_text "Question from second tab"
      assert_field "Your question", with: "First tab draft"
      click_button "Expand conversation"
      visit course_path(courses(:composition), locale: :en)
      click_button "Open course assistant"
      assert_no_text "Question from second tab"
      assert_field "Your question", with: ""
      visit course_path(@course, locale: :en)
      assert_selector "dialog[open][data-expanded=true]"
      assert_field "Your question", with: "First tab draft"
    end
  ensure
    second&.close
  end

  test "content refresh preserves the composer and quote and detects an outdated selection" do
    lesson = lessons(:pitch)
    visit course_lesson_path(@course, lesson, locale: :en)
    select_passage
    click_button "Ask about this passage"
    assert_text "Ask for an explanation"
    fill_in "Your question", with: "Keep my question"
    lesson.update!(body: "A revised example from another tab.")
    assert_button "Course updated — refresh content", wait: 5
    click_button "Course updated — refresh content"
    assert_selector ".lesson-content", text: "A revised example from another tab."
    assert_selector "dialog[open]"
    assert_field "Your question", with: "Keep my question"
    assert_selector "[data-conversation-target=quoteText]", text: "Listen to a high note"
    click_button "Send question"
    assert_text "This material has changed."
    assert_equal 0, Exchange.count
    click_button "Remove"
    click_button "Send question"
    assert_text "Waiting to start"
    assert_equal "A revised example from another tab.", Exchange.last.lesson_context["body"]
  end

  test "draft overview and lessons share discussion while publication opens a separate tutor" do
    generation = CourseGeneration.submit!(topic: "Sound", language: "en", request_key: SecureRandom.uuid)
    draft = generation.course
    lesson = draft.lessons.create!(position: 1, title: "Draft pitch", body: "A draft example.")
    generation.update!(status: :completed, lesson_count: 1)
    visit generation_path(generation, locale: :en)
    click_button "Open course assistant"
    assert_selector "#lesson-chat-heading", text: "Draft assistant"
    assert_selector "[data-activity-id]", text: "Ready for review"
    fill_in "Your question", with: "A private idea"
    click_button "Send question"
    assert_text "Waiting to start"
    perform_enqueued_jobs
    assert_text "A high note has a higher frequency."
    click_link "Preview draft"
    assert_selector "[data-conversation-target=contextLabel]", text: lesson.title
    assert_text "A private idea"
    fill_in "Your question", with: "Unsent editing idea"
    click_button "Approve and add to library"
    assert_selector "h1", text: draft.title
    assert_no_selector "dialog[open]"
    click_button "Open course assistant"
    assert_selector "#lesson-chat-heading", text: "Course tutor"
    assert_no_text "A private idea"
    assert_field "Your question", with: ""
  end

  private

  def select_passage
    element = find(".lesson-content p")
    page.execute_script(<<~JS, element)
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(arguments[0]);
      selection.removeAllRanges();
      selection.addRange(range);
    JS
  end
end
