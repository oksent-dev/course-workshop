require "test_helper"

class DraftsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @settings = Rails.configuration.x.local_authoring
    @previous_enabled = @settings.enabled
    @settings.enabled = true
    @local = { "REMOTE_ADDR" => "127.0.0.1" }
    @course = Course.create!(category: categories(:music), slug: "private-draft", title: "Private draft", description: "Review first.", language: "en")
    @lesson = @course.lessons.create!(title: "Draft lesson", position: 1, body: "## Example\n\n<script>alert(1)</script>")
  end

  teardown { @settings.enabled = @previous_enabled }

  test "draft cards filter their own catalog and retain category and lesson when changing language" do
    other = Course.create!(category: Category.create!(name: "Science"), slug: "science-draft", title: "Science draft", description: "Explore science.", language: "en")
    CourseCovers::Import.call(course: @course, path: Rails.root.join("db/seeds/images/commute-times.png"))
    get drafts_path(locale: :en), headers: @local
    assert_select "[data-course-card]", count: 2
    assert_select "[data-course-card] img", count: 1
    assert_select "[data-course-card] progress", count: 0
    assert_select "[data-course-card]", text: /Saved lessons: 1/
    assert_select "[data-primary-navigation] a[aria-current=page]", "Drafts"
    get drafts_path(locale: :en, category: @course.category_id), headers: @local
    assert_select "[data-course-card]", count: 1
    assert_select "[data-course-card] a[href=?]", draft_path(@course.id, locale: :en), minimum: 1
    assert_select "a[hreflang=pl][href=?]", drafts_path(locale: :pl, category: @course.category_id)
    assert_select "[data-course-card]", text: /#{other.title}/, count: 0
    get drafts_path(locale: :en, category: 0), headers: @local
    assert_response :not_found
    get draft_path(@course.id, locale: :en, lesson_id: @lesson.id), headers: @local
    assert_select "a[hreflang=pl][href=?]", draft_path(@course.id, locale: :pl, lesson_id: @lesson.id)
    assert_equal 0, LessonProgress.count
  end

  test "drafts stay out of the library and all public reader endpoints" do
    get localized_root_path(locale: :en), headers: @local
    assert_select "a", text: @course.title, count: 0
    get course_path(@course, locale: :en), headers: @local
    assert_response :not_found
    get course_lesson_path(@course, @lesson, locale: :en), headers: @local
    assert_response :not_found
    post course_lesson_completion_path(@course, @lesson, locale: :en), headers: @local
    assert_response :not_found
    get course_lesson_conversation_path(@course, @lesson, locale: :en), headers: @local
    assert_response :not_found
    assert_equal 0, LessonProgress.count
  end

  test "local preview is sanitized and does not count as studying" do
    get draft_path(@course.id, locale: :en), headers: @local
    assert_response :success
    assert_select ".lesson-content script", count: 0
    assert_select ".lesson-content", text: /<script>/
    assert_equal 0, LessonProgress.count
    get draft_path(@course.id, lesson_id: lessons(:pitch).id, locale: :en), headers: @local
    assert_response :not_found
  end

  test "approval publishes only the reviewed revision" do
    Drafts::Editor.save_lesson(course_id: @course.id, expected_revision: 0, lesson_id: @lesson.id, title: "Updated", body: "New material.")
    patch draft_path(@course.id, locale: :en), params: { revision: 0 }, headers: @local
    assert_response :unprocessable_content
    assert_select "[role=alert]", /draft has changed/
    assert @course.reload.draft?
    patch draft_path(@course.id, locale: :en), params: { revision: 1 }, headers: @local
    assert_redirected_to course_path(@course, locale: :en)
    follow_redirect!
    assert_select "[role=status]", "The course has been added to your library."
    assert @course.reload.published?
    assert_equal 2, @course.revision
  end

  test "disabled, remote and production requests cannot preview or publish drafts" do
    [ { "REMOTE_ADDR" => "203.0.113.1" }, @local ].each_with_index do |headers, index|
      @settings.enabled = index.zero?
      get draft_path(@course.id, locale: :en), headers: headers
      assert_response :not_found
      patch draft_path(@course.id, locale: :en), params: { revision: 0 }, headers: headers
      assert_response :not_found
    end
    @settings.enabled = true
    previous_env = Rails.env
    Rails.env = "production"
    get drafts_path(locale: :en), headers: @local
    assert_response :not_found
    assert_raises(Drafts::Error) { CourseMcp::Server.build }
  ensure
    Rails.env = previous_env if previous_env
  end

  test "empty or invalid drafts cannot be approved" do
    @lesson.destroy!
    patch draft_path(@course.id, locale: :en), params: { revision: 0 }, headers: @local
    assert_response :unprocessable_content
    @course.lessons.create!(position: 2, title: "Wrong order", body: "Read.")
    patch draft_path(@course.id, locale: :en), params: { revision: 0 }, headers: @local
    assert_response :unprocessable_content
    assert @course.reload.draft?
  end
end
