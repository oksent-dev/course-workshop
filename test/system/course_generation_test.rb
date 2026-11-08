require "application_system_test_case"
require_relative "../support/fake_course_generator"

class CourseGenerationSystemTest < ApplicationSystemTestCase
  include GenerationTestHelpers

  setup do
    @ai = Rails.configuration.x.local_ai
    @authoring = Rails.configuration.x.local_authoring
    @old = [ @ai.enabled, @ai.generator, @authoring.enabled ]
    @ai.enabled = @authoring.enabled = true
    @ai.generator = FakeCourseGenerator.new
  end

  teardown { @ai.enabled, @ai.generator, @authoring.enabled = @old }

  test "generate from the form, reload progress, review, approve and start learning" do
    AiSetting.current.update!(reasoning_effort: "medium")
    visit localized_root_path(locale: :pl)
    click_link "Utwórz kurs"
    fill_in "Czego chcesz się nauczyć?", with: "Active Record: relacje i walidacje"
    assert_no_select "Liczba lekcji"
    click_button "Przygotuj plan kursu"
    assert_text "Oczekiwanie na rozpoczęcie"
    assert_selector "[data-course-ai-reasoning=medium]", text: "Poziom rozumowania: Średni"
    assert_selector "[data-course-date=created]", text: "Utworzono:"
    page.refresh
    assert_text "Dobieranie zakresu i kolejności lekcji"
    find_button("Anuluj generowanie").send_keys(:tab, [ :shift, :tab ])
    perform_enqueued_jobs
    assert_text "Przejrzyj plan kursu"
    assert_selector "#generation-status-heading:focus"
    assert_empty CourseGeneration.last.course.lessons
    page.refresh
    find_button("Zatwierdź plan i wygeneruj lekcje").send_keys(:enter)
    assert_text "Oczekiwanie na rozpoczęcie"
    perform_course_steps
    assert_text "Gotowy do przeglądu"
    assert_selector "[data-course-date=generated]", text: "Wygenerowano:"
    assert_text "Zapisano 3 z 3 lekcji"
    perform_enqueued_jobs
    assert_text "Okładka zapisana"
    assert_selector "#cover-heading + p", text: "Okładka zapisana"
    switch_interface_language("English")
    assert_text "Ready for review"
    assert_selector "[data-course-ai-reasoning=medium]", text: "Reasoning: Medium"
    assert_selector "[data-course-date=generated]", text: "Generated:"
    generation = CourseGeneration.last
    click_link "Drafts", exact: true
    click_link generation.course.title
    assert_current_path generation_path(generation, locale: :en)
    assert_selector "h1", text: "Course plan and status"
    assert_button "Approve and add to library"
    click_link "Preview draft"
    within("[data-draft-actions]") { click_link "Course plan and status" }
    assert_current_path generation_path(generation, locale: :en)
    find_button("Approve and add to library").send_keys(:enter)
    click_link "Start the first lesson"
    assert_selector "h1", text: "Lesson 1"
    assert_button "Mark complete"
  end

  test "a partial failure can be resumed on a narrow screen without duplicating lessons" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 780, deviceScaleFactor: 1, mobile: false)
    visit new_generation_path(locale: :en)
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    fill_in "What would you like to learn?", with: "Associations"
    click_button "Prepare course plan"
    assert_text "Waiting to start"
    perform_enqueued_jobs
    assert_text "Review your course plan"
    click_button "Approve plan and generate lessons"
    assert_text "Waiting to start"
    @ai.generator.fail_after = 1
    perform_course_steps
    assert_text "Generation interrupted"
    assert_text "1 of 3 lessons saved"
    first_id = CourseGeneration.last.course.lessons.first.id
    @ai.generator.fail_after = nil
    click_button "Resume generation"
    assert_text "Waiting to start"
    perform_course_steps
    assert_text "Ready for review"
    assert_equal first_id, CourseGeneration.last.course.lessons.first.id
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "queued generation can be cancelled without losing the draft" do
    visit new_generation_path(locale: :en)
    fill_in "What would you like to learn?", with: "Associations"
    click_button "Prepare course plan"
    assert_text "Waiting to start"
    click_button "Cancel generation"
    assert_text "Generation cancelled"
    perform_enqueued_jobs
    assert_empty @ai.generator.calls
    click_link "Preview draft"
    assert_button "Approve and add to library", disabled: true
  end

  test "a failed cover can be retried by keyboard while lessons remain ready" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 780, deviceScaleFactor: 1, mobile: false)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit new_generation_path(locale: :en)
    fill_in "What would you like to learn?", with: "Associations"
    click_button "Prepare course plan"
    assert_text "Waiting to start"
    perform_enqueued_jobs
    assert_text "Review your course plan"
    click_button "Approve plan and generate lessons"
    assert_text "Waiting to start"
    perform_course_steps
    @ai.cover_generator.error = "usage_limit"
    perform_enqueued_jobs
    assert_text "Ready for review"
    assert_text "Cover could not be created"
    assert_text "The Codex image allowance has been reached"
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    lesson_ids = CourseGeneration.last.course.lessons.pluck(:id)
    @ai.cover_generator.error = nil
    find_button("Retry cover").send_keys(:enter)
    assert_text "Waiting to create the cover"
    perform_enqueued_jobs
    assert_text "Cover saved"
    assert_equal lesson_ids, CourseGeneration.last.course.lessons.pluck(:id)
    assert_equal 4, @ai.generator.calls.size
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "moving focus between controls never restarts the form entrance" do
    visit new_generation_path(locale: :en)
    assert_selector "form [name='course_generation[language]']"
    page.execute_script(<<~JS)
      window.replayedEntrances = 0;
      const form = document.querySelector('form[data-motion="enter"]');
      form.addEventListener('animationstart', () => window.replayedEntrances++);
      form.querySelector('textarea').focus();
    JS
    find("select").click
    find("select").send_keys(:escape)
    find("textarea").click
    find("select").click
    find("select").send_keys(:escape)
    find("h1").click
    assert_equal 0, page.evaluate_async_script("const done = arguments[0]; setTimeout(() => done(window.replayedEntrances), 650)")
    assert_equal "1", page.evaluate_script("getComputedStyle(document.querySelector('form')).opacity")
  end
end
