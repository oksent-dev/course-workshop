require "test_helper"
require_relative "../../support/fake_course_generator"

class CourseMcpGenerationServerTest < ActiveSupport::TestCase
  setup do
    @old = [ Rails.configuration.x.local_ai.enabled, Rails.configuration.x.local_authoring.enabled ]
    Rails.configuration.x.local_ai.enabled = Rails.configuration.x.local_authoring.enabled = true
    @generation = CourseGeneration.submit!(topic: "Active Record", language: "en", request_key: SecureRandom.uuid)
    @token = @generation.claim!(1)
    @server = CourseMcp::GenerationServer.new(generation_id: @generation.id, token: @token).build
  end

  teardown { Rails.configuration.x.local_ai.enabled, Rails.configuration.x.local_authoring.enabled = @old }

  test "the state supplies reusable category IDs and planning preserves their labels" do
    catalog = call("read_generation").dig("structuredContent", "categories")
    assert_includes catalog, { "id" => categories(:music).id, "name" => "Music" }
    assert_not_includes catalog.map { |row| row["name"] }, "Drafts"
    assert_no_difference "Category.count" do
      result = call("plan_course", **plan_arguments.except(:category).merge(category_id: categories(:music).id))
      assert_not result["isError"]
    end
    assert_equal categories(:music), @generation.course.reload.category
  end

  test "new categories are created only through an exclusive name selection" do
    args = plan_arguments
    assert call("plan_course", **args.merge(category_id: categories(:music).id))["isError"]
    assert call("plan_course", **args.except(:category))["isError"]
    assert_difference "Category.count", 1 do
      assert_not call("plan_course", **args)["isError"]
    end
    assert_equal "Programming", @generation.course.reload.category.name
  end

  test "the scoped catalog exposes no other courses, files or publication tools" do
    list = JSON.parse(@server.handle_json(JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list"))).dig("result", "tools")
    assert_equal CourseMcp::GenerationServer::TOOL_NAMES.sort, list.map { |tool| tool["name"] }.sort
    assert call("read_generation", course_id: courses(:listening).id)["isError"]
    assert call("create_course_draft")["isError"]
    assert call("plan_course", **plan_arguments.merge(language: "pl"))["isError"]
    assert_equal @generation.course_id, call("read_generation").dig("structuredContent", "course", "id")
    invalid_server = CourseMcp::GenerationServer.new(generation_id: @generation.id, token: "wrong").build
    assert_equal "inactive_generation", call("read_generation", server: invalid_server).dig("structuredContent", "code")
    Rails.configuration.x.local_ai.enabled = false
    assert_equal "disabled", call("read_generation").dig("structuredContent", "code")
  end

  test "plan and lesson writes are idempotent and positions preserve IDs" do
    args = plan_arguments
    first = call("plan_course", **args)
    assert_equal first["structuredContent"], call("plan_course", **args)["structuredContent"]
    assert_equal "plan_exists", call("plan_course", **plan_arguments).dig("structuredContent", "code")
    assert call("save_generated_lesson", position: 1, body: FakeCourseGenerator::BODY, request_key: SecureRandom.uuid)["isError"]
    start_writing
    write = { position: 1, body: FakeCourseGenerator::BODY, request_key: SecureRandom.uuid }
    saved = call("save_generated_lesson", **write)
    assert_equal saved["structuredContent"], call("save_generated_lesson", **write)["structuredContent"]
    changed = call("save_generated_lesson", **write.merge(body: "#{FakeCourseGenerator::BODY}\nA correction.", request_key: SecureRandom.uuid))
    assert_equal saved.dig("structuredContent", "lesson", "id"), changed.dig("structuredContent", "lesson", "id")
    assert_equal 1, @generation.course.lessons.count
    assert_equal 3, @generation.course.reload.revision
    assert_equal "request_conflict", call("save_generated_lesson", **write.merge(position: 2)).dig("structuredContent", "code")
  end

  test "invalid content and wrong plan sizes roll back all state and receipts" do
    assert_no_difference [ "DraftOperation.count", "Category.count" ] do
      assert call("plan_course", **plan_arguments.merge(lesson_titles: []))["isError"]
      assert call("plan_course", **plan_arguments.merge(lesson_titles: (1..61).map(&:to_s)))["isError"]
      assert call("plan_course", **plan_arguments.merge(title: " ", category: "Rollback category"))["isError"]
    end
    assert_empty @generation.reload.plan
    call("plan_course", **plan_arguments)
    start_writing
    assert_no_difference [ "Lesson.count", "DraftOperation.count" ] do
      assert call("save_generated_lesson", position: 4, body: FakeCourseGenerator::BODY, request_key: SecureRandom.uuid)["isError"]
      assert call("save_generated_lesson", position: 1, body: "#{FakeCourseGenerator::BODY}\n![image](https://example.com/image.png)", request_key: SecureRandom.uuid)["isError"]
    end
  end

  test "ordinary authoring and publication cannot change a generation before it completes" do
    error = assert_raises(Drafts::Error) { Drafts::Editor.publish(course_id: @generation.course_id, expected_revision: 0) }
    assert_equal "generation_busy", error.code
    error = assert_raises(Drafts::Error) do
      Drafts::Editor.save_lesson(course_id: @generation.course_id, expected_revision: 0, title: "Outside edit", body: "Text")
    end
    assert_equal "generation_busy", error.code
  end

  test "a lesson needs a visual or a complete request for an illustration" do
    call("plan_course", **plan_arguments)
    start_writing
    body = "A useful conceptual explanation. " * 12
    args = { position: 1, body: body, request_key: SecureRandom.uuid }
    assert_equal "missing_visual", call("save_generated_lesson", **args).dig("structuredContent", "code")
    assert call("save_generated_lesson", **args.merge(illustration_prompt: "A concept"))["isError"]
    result = call("save_generated_lesson", **args.merge(illustration_prompt: "Show the relationship clearly", illustration_alt: "A comparison"))
    assert_not result["isError"]
    assert_equal "Show the relationship clearly", @generation.reload.illustration_prompt
  end

  private

  def start_writing
    @generation.reload.advance!(1, 0)
    @generation.approve_plan!(1, @generation.course.reload.revision)
    @token = @generation.claim!(1)
    @server = CourseMcp::GenerationServer.new(generation_id: @generation.id, token: @token).build
  end

  def plan_arguments
    { request_key: SecureRandom.uuid, title: "Associations", description: "A practical course.", category: "Programming", lesson_titles: %w[Parents Children Validation] }
  end

  def call(name, server: @server, **arguments)
    response = JSON.parse(server.handle_json(JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments })))
    response["result"] || { "isError" => true }
  end
end
