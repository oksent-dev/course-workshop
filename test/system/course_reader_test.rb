require "application_system_test_case"

class CourseReaderTest < ApplicationSystemTestCase
  test "category navigation keeps its selection and loaded covers have a usable fallback" do
    category = Category.create!(name: "Statistics")
    course = category.courses.create!(title: "Everyday statistics", slug: "everyday-statistics", description: "Understand everyday data.", language: "en", status: :published)
    CourseCovers::Import.call(course: course, path: Rails.root.join("db/seeds/images/commute-times.png"))
    visit localized_root_path(locale: :en)
    assert_selector "[data-course-card]", count: 3
    within("nav[aria-label='Filter courses by category']") { find_link("Statistics").send_keys(:enter) }
    assert_selector "[data-course-card]", count: 1
    assert_selector "[data-course-card] img" do |image|
      image.evaluate_script("this.complete && this.naturalWidth > 0")
    end
    assert_no_selector "[data-course-cover-target=fallback]"
    click_link "Polski"
    assert_current_path localized_root_path(locale: :pl, category: category.id)
    assert_selector "[data-course-card]", count: 1
    page.execute_script("document.querySelector('[data-course-card] img').src = '/missing-course-cover.webp'")
    assert_selector "[data-course-cover-target=fallback]"
    assert_no_selector "[data-course-card] img"
    click_link "Everyday statistics"
    assert_selector "h1", text: course.title
  end

  test "a reader can follow the demo course and switch the interface language mid-lesson" do
    Rails.application.load_seed
    visit localized_root_path(locale: :pl)

    within("section", text: "Statystyka na co dzień") { click_link "Statystyka na co dzień" }
    assert_selector "h1", text: "Statystyka na co dzień"
    click_link "Zacznij od pierwszej lekcji"
    assert_selector "h1", text: "Pięć poranków"
    click_link "Następna lekcja"
    assert_selector "h1", text: "Średnia i mediana"

    click_link "English"
    assert_selector "html[lang=en]"
    assert_selector "h1[lang=pl]", text: "Średnia i mediana"
    assert_text "Lesson 2 of 3"
    find("summary", text: "Compare your answer").click
    assert_text "Suma wzrosła do 60 minut"
    click_link "Next lesson"
    assert_selector "h1", text: "Dobierz miarę do pytania"
    assert_no_link "Next lesson"

    click_link "Previous lesson"
    assert_selector "h1", text: "Średnia i mediana"
    click_link "Next lesson"
    click_link "Back to course outline"
    assert_selector "h1", text: "Statystyka na co dzień"
    click_link "Your course library"
    assert_selector "h1", text: "Your course library"
  end
end
