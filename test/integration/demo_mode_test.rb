require "test_helper"

class DemoModeTest < ActionDispatch::IntegrationTest
  setup do
    @previous = [ Rails.configuration.x.demo_mode, Rails.configuration.x.local_ai.enabled,
      Rails.configuration.x.local_authoring.enabled ]
    Rails.configuration.x.demo_mode = true
    Rails.configuration.x.local_ai.enabled = true
    Rails.configuration.x.local_authoring.enabled = true
    DemoCatalog.prepare!
    @course = Course.find_by!(slug: DemoMode::COURSE_SLUGS.first)
    host! "localhost"
    @local = { "REMOTE_ADDR" => "127.0.0.1" }
  end

  teardown do
    Rails.configuration.x.demo_mode, Rails.configuration.x.local_ai.enabled,
      Rails.configuration.x.local_authoring.enabled = @previous
  end

  test "public previews do not expose saved preferences or private generations" do
    AiSetting.current.update!(style_instructions: "Private saved preference")
    %i[pl en].each do |locale|
      get settings_path(locale: locale), headers: @local
      assert_response :success
      assert_select "fieldset[disabled] textarea", text: ""
      assert_not_includes response.body, "Private saved preference"
      assert_select "a[href=?]", new_generation_path(locale: locale)
      get new_generation_path(locale: locale), headers: @local
      assert_response :success
      assert_select "fieldset[disabled] textarea[name='course_generation[topic]']"
      assert_select "#recent-heading", count: 0
    end
  end

  test "demo blocks direct mutations and conversation access even with local flags enabled" do
    assert_not LocalAi.enabled?
    assert_not LocalAuthoring.enabled?
    assert_not LocalGeneration.enabled?
    assert_no_difference [ "Course.count", "CourseGeneration.count", "AiRun.count", "Exchange.count" ] do
      post generations_path(locale: :en), headers: @local, params: { course_generation: { topic: "Forged request" } }
      assert_response :not_found
      patch settings_path(locale: :en), headers: @local, params: { ai_setting: { style_instructions: "Override" } }
      assert_response :not_found
      get course_conversation_path(@course, locale: :en), headers: @local
      assert_response :not_found
      post course_conversation_exchanges_path(@course, locale: :en), headers: @local, params: { question: "Hello" }
      assert_response :not_found
      get drafts_path(locale: :en), headers: @local
      assert_response :not_found
      patch draft_path(@course, locale: :en), headers: @local
      assert_response :not_found
    end
  end

  test "only packaged courses are public including direct lesson and completion URLs" do
    get localized_root_path(locale: :en), headers: @local
    assert_response :success
    DemoMode::COURSE_SLUGS.each { |slug| assert_select "a[href=?]", course_path(slug, locale: :en) }
    assert_select "a[href=?]", course_path(courses(:listening), locale: :en), count: 0
    assert_equal "private, no-store", response.headers["Cache-Control"]
    course = courses(:listening)
    lesson = course.lessons.first
    get course_path(course, locale: :en), headers: @local
    assert_response :not_found
    get course_lesson_path(course, lesson, locale: :en), headers: @local
    assert_response :not_found
    post course_lesson_completion_path(course, lesson, locale: :en), headers: @local
    assert_response :not_found
  end

  test "different localhost browsers have separate durable progress in demo" do
    path = course_lesson_completion_path(@course, @course.lessons.first, locale: :en)
    first = open_session { |session| session.host! "localhost" }
    second = open_session { |session| session.host! "localhost" }
    assert_difference "LearnerProfile.count", 2 do
      first.post path, headers: @local
      second.get course_path(@course, locale: :en), headers: @local
    end
    assert_equal 1, LessonProgress.where(lesson: @course.lessons.first).where.not(completed_at: nil).count
    first.get course_path(@course, locale: :en), headers: @local
    assert_equal "private, no-store", first.response.headers["Cache-Control"]
    assert_no_difference "LearnerProfile.count" do
      first.delete path, headers: @local
    end
    assert_equal 0, LessonProgress.where(lesson: @course.lessons.first).where.not(completed_at: nil).count
  end

  test "all lessons render their visual content and exercise without external media" do
    Course.where(slug: DemoMode::COURSE_SLUGS).each do |course|
      course.lessons.each do |lesson|
        get course_lesson_path(course, lesson, locale: course.language), headers: @local
        assert_response :success
        assert_select ".lesson-exercise", count: 1
        assert_select ".lesson-content table, .lesson-content img, [data-controller=lesson-block]", minimum: 1
        assert_select ".lesson-image-unavailable:not(.hidden)", count: 0
        assert_select ".lesson-content img[src^='http']", count: 0
        assert_select "[data-controller=conversation]", count: 0
        assert_select "#demo-chat-panel fieldset[disabled]"
      end
    end
  end
end
