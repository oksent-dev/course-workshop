require "application_system_test_case"
require_relative "../support/fake_editor"

class DraftEditingSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @ai, @authoring = Rails.configuration.x.local_ai, Rails.configuration.x.local_authoring
    @previous = [ @ai.enabled, @authoring.enabled, @ai.editor ]
    @ai.enabled = @authoring.enabled = true
    @ai.editor = FakeEditor.new
    @course = courses(:listening)
    @course.update!(status: :draft)
  end

  teardown { @ai.enabled, @authoring.enabled, @ai.editor = @previous }

  test "quoted editing refreshes the lesson preserves conversation and supports preview and undo" do
    visit draft_path(@course.id, locale: :en, lesson_id: lessons(:pitch).id)
    paragraph = find(".lesson-content p")
    page.execute_script(<<~JS, paragraph)
      const range = document.createRange(); range.selectNodeContents(arguments[0]);
      const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
    JS
    click_button "Ask about this passage"
    fill_in "Your question", with: "Improve this explanation"
    click_button "Send question"
    assert_text "Waiting to start"
    assert_equal lessons(:pitch).id, Exchange.last.lesson_context["lesson_id"]
    perform_enqueued_jobs
    assert_selector ".lesson-content", text: "Compare the observations", wait: 8
    assert_selector "dialog[open]"
    assert_text "The selected lesson now has a clearer explanation"
    find("summary", text: "Review change").click
    assert_text "Before ·"
    fill_in "Your question", with: "Keep my next request"
    click_button "Undo this change"
    assert_text "Change undone", wait: 5
    assert_field "Your question", with: "Keep my next request"
    assert_equal "Pitch", lessons(:pitch).reload.title
    click_button "Course updated — refresh content"
    assert_selector ".lesson-content", text: "Listen to a high note"
    page.refresh
    assert_selector "dialog[open]"
    assert_text "Improve this explanation"
    assert_field "Your question", with: "Keep my next request"
  end

  test "partial success stays visible and undoable after an interrupted answer" do
    @ai.editor.failure = true
    visit draft_path(@course.id, locale: :en, lesson_id: lessons(:pitch).id)
    click_button "Open course assistant"
    fill_in "Your question", with: "Improve the lesson"
    click_button "Send question"
    assert_text "Waiting to start"
    perform_enqueued_jobs
    assert_button "Undo this change", wait: 5
    assert_text "Saved · revision 1"
    assert Exchange.last.failed?
    click_button "Undo this change"
    assert_text "Change undone"
    assert_equal "Pitch", lessons(:pitch).reload.title
  end
end
