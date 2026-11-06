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
    find("summary", text: "Ask about this lesson").click
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
    find("summary", text: "Zapytaj o tę lekcję").click
    assert_text "Give me another example"
    assert_field "Twoje pytanie"
    assert_selector "h1", text: lesson.title
  end

  test "a cancelled queued reply and an unavailable runtime are understandable" do
    lesson = lessons(:pitch)
    visit course_lesson_path(lesson.course, lesson, locale: :en)
    find("summary", text: "Ask about this lesson").click
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
end
