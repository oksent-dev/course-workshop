require "test_helper"

class CourseMcpServerTest < ActiveSupport::TestCase
  setup do
    @settings = Rails.configuration.x.local_authoring
    @previous_enabled = @settings.enabled
    @settings.enabled = true
    @server = CourseMcp::Server.build
  end

  teardown { @settings.enabled = @previous_enabled }

  test "authors can list and reuse category IDs without creating translated duplicates" do
    catalog = call("list_categories").dig("structuredContent", "categories")
    assert_includes catalog, { "id" => categories(:music).id, "name" => "Music" }
    assert_no_difference "Category.count" do
      result = call("create_course_draft", **metadata.except(:category), category_id: categories(:music).id, request_key: SecureRandom.uuid)
      assert_equal categories(:music).id, result.dig("structuredContent", "course", "category_id")
      assert_equal "Music", result.dig("structuredContent", "course", "category")
    end
  end

  test "the protocol exposes bounded schemas and no publication, deletion or file tools" do
    tools = rpc("tools/list").fetch("result").fetch("tools")
    assert_equal %w[create_course_draft get_authoring_guide list_categories list_courses read_course read_lesson reorder_draft_lessons save_draft_lesson update_course_draft], tools.map { |tool| tool["name"] }.sort
    tools.each do |tool|
      assert_equal false, tool.dig("inputSchema", "additionalProperties")
      assert tool["outputSchema"]
    end
    assert_includes call("get_authoring_guide").dig("structuredContent", "guide"), "expected_revision"
    assert rpc("tools/call", name: "list_courses", arguments: { limit: 1000 }).dig("result", "isError")
    assert rpc("tools/call", name: "list_courses", arguments: { path: "/etc/passwd" }).dig("result", "isError")
    assert rpc("tools/call", name: "create_course_draft", arguments: metadata.merge(request_key: "not-a-uuid")).dig("result", "isError")
    assert rpc("tools/call", name: "create_course_draft", arguments: metadata.merge(title: "a\0b", request_key: SecureRandom.uuid)).dig("result", "isError")
  end

  test "create two lessons, correct one, reorder, and read using stable IDs" do
    course = create_draft
    first = save_lesson(course, title: "Pierwszy pomiar")
    second = save_lesson(first.fetch("course"), title: "Drugi pomiar")
    edited = call("save_draft_lesson", course_id: course["id"], expected_revision: 2,
      lesson_id: first.dig("lesson", "id"), title: "Poprawiony pomiar", body: "## Poprawka\n\nZażółć gęślą jaźń.", request_key: SecureRandom.uuid)
    assert_equal false, edited["isError"], edited.inspect
    assert_equal first.dig("lesson", "id"), edited.dig("structuredContent", "lesson", "id")
    ids = [ second.dig("lesson", "id"), first.dig("lesson", "id") ]
    2.times do |index|
      response = call("reorder_draft_lessons", course_id: course["id"], expected_revision: 3 + index,
        lesson_ids: ids, request_key: SecureRandom.uuid)
      assert_equal false, response["isError"], response.inspect
    end
    outline = call("read_course", course_id: course["id"]).fetch("structuredContent")
    assert_equal ids, outline["lessons"].map { |lesson| lesson["id"] }
    assert_equal [ 1, 2 ], outline["lessons"].map { |lesson| lesson["position"] }
    assert_equal "draft", outline.dig("course", "status")
    assert_equal 5, outline.dig("course", "revision")
    body = call("read_lesson", course_id: course["id"], lesson_id: ids.last)
    assert_includes body.dig("structuredContent", "lesson", "body"), "Zażółć"
  end

  test "identical retries return the original result while changed payloads and stale revisions fail" do
    key = SecureRandom.uuid
    first = call("create_course_draft", **metadata, request_key: key)
    assert_no_difference [ "Course.count", "DraftOperation.count" ] do
      assert_equal first["structuredContent"], call("create_course_draft", **metadata, request_key: key)["structuredContent"]
    end
    assert_error "request_conflict", call("create_course_draft", **metadata.merge(title: "Changed"), request_key: key)
    course = first.dig("structuredContent", "course")
    arguments = { course_id: course["id"], expected_revision: 0, title: "Lesson", body: "Read this.", request_key: SecureRandom.uuid }
    saved = call("save_draft_lesson", **arguments)
    assert_equal saved["structuredContent"], call("save_draft_lesson", **arguments)["structuredContent"]
    assert_error "revision_conflict", call("save_draft_lesson", **arguments.merge(title: "Stale", request_key: SecureRandom.uuid))
    assert_equal 1, Course.find(course["id"]).lessons.count
    assert_equal 1, Course.find(course["id"]).revision
    assert_equal 2, DraftOperation.count
  end

  test "published courses, foreign lessons and incomplete reorder lists cannot be changed" do
    course = create_draft
    saved = save_lesson(course)
    assert_error "not_draft", call("save_draft_lesson", course_id: courses(:listening).id, expected_revision: 0,
      title: "Forbidden", body: "No", request_key: SecureRandom.uuid)
    assert_error "not_found", call("save_draft_lesson", course_id: course["id"], lesson_id: lessons(:pitch).id, expected_revision: 1,
      title: "Forbidden", body: "No", request_key: SecureRandom.uuid)
    assert_error "not_found", call("read_lesson", course_id: course["id"], lesson_id: lessons(:pitch).id)
    assert_error "invalid_order", call("reorder_draft_lessons", course_id: course["id"], expected_revision: 1,
      lesson_ids: [], request_key: SecureRandom.uuid)
    assert_equal [ saved.dig("lesson", "id") ], Course.find(course["id"]).lessons.ids
  end

  test "failed writes roll back receipts and new categories and leave revisions unchanged" do
    count = Category.count
    bad = metadata.merge(title: " ", category: "Temporary category")
    assert_error "invalid_content", call("create_course_draft", **bad, request_key: SecureRandom.uuid)
    assert_equal count, Category.count
    assert_equal 0, DraftOperation.count
    course = create_draft
    key = SecureRandom.uuid
    bad_bodies = [ " ", "a\0b", "```mermaid\nflowchart TD\nclick A evil\n```", "![x](https://example.com/x.png)",
      "```exercise\n#{ { prompt: '![x](image:missing)', answer: '4' }.to_json }\n```" ]
    bad_bodies.each do |body|
      assert_error "invalid_content", call("save_draft_lesson", course_id: course["id"], expected_revision: 0,
        title: "Invalid", body: body, request_key: key)
    end
    assert_equal 0, Course.find(course["id"]).revision
    assert_equal 1, DraftOperation.count
    saved = call("save_draft_lesson", course_id: course["id"], expected_revision: 0, title: "Fixed", body: "Valid.", request_key: key)
    assert_equal false, saved["isError"]
  end

  test "metadata updates and pagination keep draft identity and existing courses intact" do
    course = create_draft
    result = call("update_course_draft", **metadata.except(:slug).merge(title: "Updated"), course_id: course["id"],
      expected_revision: 0, request_key: SecureRandom.uuid).fetch("structuredContent")
    assert_equal course["id"], result.dig("course", "id")
    assert_equal "Updated", result.dig("course", "title")
    first = call("list_courses", limit: 1).fetch("structuredContent")
    second = call("list_courses", limit: 1, after_id: first["next_after_id"]).fetch("structuredContent")
    assert_not_equal first["courses"].first["id"], second["courses"].first["id"]
    assert_equal [ course["id"] ], call("list_courses", status: "draft").dig("structuredContent", "courses").map { |row| row["id"] }
    assert_equal "Listening closely", courses(:listening).reload.title
  end

  test "disablement is enforced again after the server has started" do
    @settings.enabled = false
    assert_error "disabled", call("list_courses")
    assert_raises(Drafts::Error) { CourseMcp::Server.build }
  end

  private

  def rpc(method, **params)
    JSON.parse(@server.handle_json(JSON.generate(jsonrpc: "2.0", id: 1, method: method, params: params)))
  end

  def call(name, **arguments)
    rpc("tools/call", name: name, arguments: arguments).fetch("result")
  end

  def metadata
    { slug: "test-draft", title: "Szkic testowy", description: "A short course.", language: "pl", category: "Practice" }
  end

  def create_draft
    call("create_course_draft", **metadata, request_key: SecureRandom.uuid).fetch("structuredContent").fetch("course")
  end

  def save_lesson(course, title: "Lesson")
    result = call("save_draft_lesson", course_id: course["id"], expected_revision: course["revision"],
      title: title, body: "A useful explanation.", request_key: SecureRandom.uuid)
    assert_equal false, result["isError"], result.inspect
    result.fetch("structuredContent")
  end

  def assert_error(code, response)
    assert_equal true, response["isError"], response.inspect
    assert_equal code, response.dig("structuredContent", "code"), response.inspect
  end
end
