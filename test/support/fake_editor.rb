require_relative "draft_editing"

class FakeEditor
  attr_accessor :failure

  def reply(exchange, token:, on_thread:, cancelled:, run: nil)
    on_thread.call("fake-editor-thread")
    server = CourseMcp::EditorServer.new(exchange_id: exchange.id, token: token)
    course = exchange.conversation.course
    lesson = course.lessons.find(exchange.lesson_context.fetch("lesson_id"))
    response = server.execute("save_lesson", request_key: SecureRandom.uuid, expected_revision: course.reload.revision,
      lesson_id: lesson.id, title: "A clearer explanation", body: DraftEditing::BODY)
    raise "Failed editor mutation" if response.error?
    raise LocalAi::Error, "unavailable" if failure
    server.execute("refresh_course_view", request_key: SecureRandom.uuid, expected_revision: course.reload.revision)
    "The selected lesson now has a clearer explanation and a comparison table."
  end
end
