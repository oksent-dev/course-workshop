require "test_helper"

class CourseMetadataTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @local = { "REMOTE_ADDR" => "127.0.0.1" }
    @ai, @authoring = Rails.configuration.x.local_ai, Rails.configuration.x.local_authoring
    @previous = [ @ai.enabled, @authoring.enabled ]
    @ai.enabled = @authoring.enabled = true
    AiSetting.current.update!(reasoning_effort: "medium", style_instructions: "Private style instruction")
    @generation = CourseGeneration.submit!(topic: "Everyday patterns", language: "en", request_key: SecureRandom.uuid)
    @course = @generation.course
    @timestamp = Time.zone.parse("2026-11-08 20:35:00")
  end

  teardown { @ai.enabled, @authoring.enabled = @previous }

  test "generation effort stays historical and dates appear in outlines drafts and both card lists" do
    assert_equal "medium", @course.generation_reasoning_effort
    AiSetting.current.update!(reasoning_effort: "high")
    @course.update!(generated_at: @timestamp)

    { en: [ "Reasoning: Medium", "08 Nov 2026" ], pl: [ "Poziom rozumowania: Średni", "08.11.2026" ] }.each do |locale, (effort, date)|
      [ generation_path(@generation, locale: locale), draft_path(@course.id, locale: locale) ].each do |path|
        get path, headers: @local
        assert_response :success
        assert_select "[data-course-ai-reasoning=medium]", text: effort
        assert_select "[data-course-date=generated] time[datetime=?]", @timestamp.iso8601, text: date
        assert_not_includes response.body, "Private style instruction"
      end
      get drafts_path(locale: locale), headers: @local
      assert_select "[data-course-card] [data-course-date=generated] time", text: date
    end

    @course.update!(status: :published)
    get course_path(@course, locale: :en), headers: @local
    assert_select "[data-course-ai-reasoning=medium]", text: "Reasoning: Medium"
    assert_select "[data-course-date=generated] time", text: "08 Nov 2026"
    get localized_root_path(locale: :pl), headers: @local
    assert_select "[data-course-card] [data-course-date=generated] time", text: "08.11.2026"
  end

  test "unfinished and manually authored courses use creation dates without inventing generation metadata" do
    @course.update!(created_at: @timestamp)
    get generation_path(@generation, locale: :en), headers: @local
    assert_select "[data-course-date=created]", text: /Created:.*08 Nov 2026/m
    assert_select "[data-course-date=generated]", count: 0

    manual = courses(:listening)
    get course_path(manual, locale: :pl), headers: @local
    assert_select "[data-course-date=created] time", count: 1
    assert_select "[data-course-ai-model], [data-course-ai-reasoning]", count: 0

    @course.update!(generation_reasoning_effort: nil)
    get draft_path(@course.id, locale: :en), headers: @local
    assert_select "[data-course-ai-reasoning]", text: "Reasoning: Not recorded"
  end

  test "status polling includes refreshed provenance" do
    get generation_path(@generation, locale: :en, format: :json), headers: @local
    previous_version = response.parsed_body.fetch("version")
    @course.update!(generated_at: @timestamp)
    get generation_path(@generation, locale: :en, format: :json), headers: @local
    assert_not_equal previous_version, response.parsed_body.fetch("version")
    metadata = Nokogiri::HTML.fragment(response.parsed_body.fetch("metadata_html"))
    assert_equal "08 Nov 2026", metadata.at_css("[data-course-date=generated] time").text
    assert_equal "Reasoning: Medium", metadata.at_css("[data-course-ai-reasoning]").text
  end
end
