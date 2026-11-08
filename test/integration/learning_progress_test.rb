require "test_helper"

class LearningProgressTest < ActionDispatch::IntegrationTest
  setup do
    @settings = Rails.configuration.x.learning_progress
    @previous_local = @settings.local_profile
    @settings.local_profile = false
    @course = courses(:listening)
    @lesson = lessons(:pitch)
    @local = { "REMOTE_ADDR" => "127.0.0.1" }
  end

  teardown do
    @settings.local_profile = @previous_local
  end

  test "two of five completions persist with a browser cookie after reopening the application" do
    3.times { |index| @course.lessons.create!(position: 40 + index, title: "Practice #{index}", body: "Try it.") }
    get lesson_path(@lesson)
    assert_equal 0, LessonProgress.where.not(completed_at: nil).count
    post completion_path(@lesson)
    assert_response :see_other
    timestamp = LessonProgress.find_by!(lesson: @lesson).completed_at
    post completion_path(@lesson)
    assert_equal timestamp, LessonProgress.find_by!(lesson: @lesson).completed_at
    post completion_path(lessons(:rhythm))

    reopened = open_session
    reopened.cookies[LearnerContext::COOKIE_NAME] = cookies[LearnerContext::COOKIE_NAME]
    reopened.get localized_root_path(locale: :en)
    reopened.assert_select "[data-course-progress] p", "2 of 5 lessons completed"
    reopened.assert_select "a[href=?]", lesson_path(@course.lessons.third), text: "Resume course"
    assert_equal 1, LearnerProfile.count
    assert_equal 2, LessonProgress.count
  end

  test "browser profiles are isolated and supplied profile IDs cannot select another learner" do
    post completion_path(@lesson)
    owner = LearnerProfile.last
    other = open_session
    other.get localized_root_path(locale: :en)
    other.assert_select "[data-course-progress] p", "0 of 2 lessons completed"
    other.delete completion_path(@lesson), params: { learner_profile_id: owner.id, key: owner.key }
    assert owner.lesson_progresses.find_by!(lesson: @lesson).completed_at?
    other.post completion_path(lessons(:rhythm)), params: { learner_profile_id: owner.id }
    assert_nil owner.lesson_progresses.find_by(lesson: lessons(:rhythm))
    assert_equal 2, LearnerProfile.count
  end

  test "local browsers share a durable profile while remote requests remain separate" do
    @settings.local_profile = true
    host! "localhost"
    post completion_path(@lesson), headers: @local
    assert_equal "local", LearnerProfile.last.key
    assert_nil cookies[LearnerContext::COOKIE_NAME]

    other = open_session
    other.host! "localhost"
    other.get localized_root_path(locale: :en), headers: @local
    other.assert_select "[data-course-progress] p", "1 of 2 lessons completed"
    other.get localized_root_path(locale: :en), headers: { "REMOTE_ADDR" => "203.0.113.1" }
    other.assert_select "[data-course-progress] p", "0 of 2 lessons completed"
    other.host! "example.com"
    other.get localized_root_path(locale: :en), headers: @local
    other.assert_select "[data-course-progress] p", "0 of 2 lessons completed"
  end

  test "production never uses the shared local profile even if enabled" do
    @settings.local_profile = true
    host! "localhost"
    previous_env = Rails.env
    Rails.env = "production"
    post completion_path(@lesson), headers: @local
    assert_not_equal "local", LearnerProfile.last.key
  ensure
    Rails.env = previous_env
  end

  test "undo is idempotent and a lesson from another course cannot be modified" do
    post completion_path(@lesson)
    2.times { delete completion_path(@lesson) }
    assert_response :see_other
    assert_nil LessonProgress.find_by!(lesson: @lesson).completed_at
    wrong_path = course_lesson_completion_path(courses(:composition), @lesson, locale: :en)
    post wrong_path
    assert_response :not_found
    delete wrong_path
    assert_response :not_found
    assert_equal 1, LessonProgress.count
  end

  test "completion streams update reader progress and undo without navigating" do
    get lesson_path(@lesson)
    visited_at = LessonProgress.last.last_opened_at
    headers = { "Accept" => "text/vnd.turbo-stream.html" }

    post completion_path(@lesson), headers: headers
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_nil response.headers["Location"]
    assert_select "turbo-stream[action=update][method=morph]", count: 3
    assert_select "turbo-stream[targets='[data-reader-progress]'] template" do
      assert_select "progress[value='1'][max='2']"
      assert_select "a[aria-current=page]", text: /Completed/
    end
    assert_select "turbo-stream[target=lesson-completion] button", text: "Mark as incomplete"
    assert_select "turbo-stream[target=lesson-navigation] a[rel=next].btn-primary"
    assert_equal visited_at, LessonProgress.last.last_opened_at

    delete completion_path(@lesson), headers: headers
    assert_response :success
    assert_select "turbo-stream[targets='[data-reader-progress]'] progress[value='0']"
    assert_select "turbo-stream[target=lesson-completion] button", text: "Mark complete"
    assert_select "turbo-stream[target=lesson-navigation] a[rel=next].btn-ghost"
    assert_nil LessonProgress.last.completed_at
  end

  test "prefetch and HEAD requests do not move the resume location" do
    get lesson_path(@lesson)
    record = LessonProgress.last
    timestamp = record.last_opened_at
    get lesson_path(lessons(:rhythm)), headers: { "X-Sec-Purpose" => "prefetch" }
    get lesson_path(lessons(:rhythm)), headers: { "Sec-Purpose" => "prefetch;prerender" }
    head lesson_path(lessons(:rhythm))
    assert_equal 1, LessonProgress.count
    assert_equal timestamp, record.reload.last_opened_at
    get localized_root_path(locale: :en)
    assert_select "a[href=?]", lesson_path(@lesson), text: "Resume course"
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    assert_select "meta[name=turbo-prefetch][content=false]"
  end

  test "the browser identity cookie is persistent, protected and rejects tampering" do
    https!
    get localized_root_path(locale: :en)
    header = Array(response.headers["Set-Cookie"]).join(";").downcase
    assert_includes header, "expires="
    assert_includes header, "httponly"
    assert_includes header, "samesite=lax"
    assert_includes header, "secure"
    cookies[LearnerContext::COOKIE_NAME] = "local"
    get localized_root_path(locale: :en)
    assert_equal 2, LearnerProfile.count
    assert_not LearnerProfile.exists?(key: "local")
  end
  private

  def lesson_path(lesson)
    course_lesson_path(@course, lesson, locale: :en)
  end

  def completion_path(lesson)
    course_lesson_completion_path(@course, lesson, locale: :en)
  end
end
