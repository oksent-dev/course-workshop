require "test_helper"

class CourseReadingTest < ActionDispatch::IntegrationTest
  test "the library filters published cards and preserves the filter when changing language" do
    category = Category.create!(name: "Statistics")
    course = category.courses.create!(title: "Everyday statistics", slug: "everyday-statistics", description: "Learn with everyday data.", language: "en", status: :published)
    hidden = Category.create!(name: "Draft category")
    hidden.courses.create!(title: "Unfinished", slug: "unfinished", description: "Not ready.", language: "en", status: :draft)

    get localized_root_path(locale: :en)
    assert_select "[data-course-card]", count: 3
    assert_select "nav[aria-label='Filter courses by category']" do
      assert_select "a", text: /All\s+3/
      assert_select "a", text: /Music\s+2/
      assert_select "a", text: /Statistics\s+1/
      assert_select "a", text: /Draft category/, count: 0
    end

    get localized_root_path(locale: :en, category: category.id)
    assert_response :success
    assert_select "[data-course-card]", count: 1
    assert_select "[data-course-card] h2", course.title
    assert_select "[data-course-card] .badge", category.name
    assert_select "nav[aria-label='Filter courses by category'] a[aria-current=page]", text: /Statistics/
    assert_select "a[hreflang=pl][href=?]", localized_root_path(locale: :pl, category: category.id)
    assert_select "[data-course-cover-target=fallback]", count: 1

    get localized_root_path(locale: :en, category: hidden.id)
    assert_response :not_found
    get localized_root_path(locale: :en, category: "not-a-category")
    assert_response :not_found
  end

  test "the library keeps its empty state when there are no courses" do
    Course.destroy_all

    get localized_root_path(locale: :en)
    assert_response :success
    assert_select "h2", "Your shelf is empty"
  end

  test "a course without lessons has an outline but no start link" do
    get course_path(courses(:composition), locale: :en)

    assert_response :success
    assert_select "h1", courses(:composition).title
    assert_select "p", "This course has no lessons yet."
    assert_select "a", text: "Start the first lesson", count: 0
  end

  test "the reader follows position even when positions have gaps" do
    course = courses(:listening)
    first_path = course_lesson_path(course, lessons(:pitch), locale: :en)
    last_path = course_lesson_path(course, lessons(:rhythm), locale: :en)

    get course_path(course, locale: :en)
    assert_select "ol a" do |links|
      assert_equal [ first_path, last_path ], links.map { |link| link["href"] }
    end

    get first_path
    assert_response :success
    assert_select "article p", "Lesson 1 of 2"
    assert_select "a[rel=next][href=?]", last_path
    assert_select "a[rel=prev]", count: 0

    get last_path
    assert_select "article p", "Lesson 2 of 2"
    assert_select "a[rel=prev][href=?]", first_path
    assert_select "a[rel=next]", count: 0
  end

  test "a lesson cannot be read under a different course" do
    get course_lesson_path(courses(:composition), lessons(:pitch), locale: :pl)
    assert_response :not_found
  end

  test "raw HTML in a lesson is rendered as text" do
    lesson = lessons(:pitch)
    lesson.update!(body: "Read the example.\n\n<script>alert(1)</script>")

    get course_lesson_path(lesson.course, lesson, locale: :en)

    assert_select "article script", count: 0
    assert_select ".lesson-content", text: /<script>alert\(1\)<\/script>/
  end
end
