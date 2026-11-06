require "application_system_test_case"

class CourseReaderTest < ApplicationSystemTestCase
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
