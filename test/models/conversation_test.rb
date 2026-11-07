require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  setup do
    @owner = LearnerProfile.create!(key: SecureRandom.hex(32))
  end

  test "one course conversation per owner and mode retains an immutable lesson snapshot" do
    course = lessons(:pitch).course
    conversation = Conversation.for_course!(course: course, learner: @owner)
    assert_equal conversation, Conversation.for_course!(course: course, learner: @owner)
    editor = Conversation.for_course!(course: course, learner: @owner, mode: "editor")
    other = Conversation.for_course!(course: course, learner: LearnerProfile.create!(key: SecureRandom.hex(32)))
    exchange = conversation.ask!(question: "Explain", lesson: lessons(:pitch), selected_text: "a note",
      request_key: SecureRandom.uuid, locale: "en")
    original = exchange.lesson_context.deep_dup
    lessons(:pitch).update!(body: "Changed later")
    assert_equal original, exchange.reload.lesson_context
    assert_equal lessons(:pitch).id, original["lesson_id"]
    assert_equal course.lessons.count, original["outline"].size
    assert_empty editor.history
    assert_empty other.history
  end

  test "known legacy histories remain intact and unknown identities stay unclaimed" do
    lesson = lessons(:pitch)
    key = SecureRandom.hex(32)
    legacy = lesson.conversations.create!(browser_key: key, runtime_thread_id: "old-thread")
    exchange = legacy.ask!(question: "Old question", request_key: SecureRandom.uuid, locale: "en")
    exchange.finish!(:completed, answer: "Saved answer")
    unknown = lesson.conversations.create!(browser_key: SecureRandom.hex(32))
    conversation = Conversation.for_course!(course: lesson.course, learner: @owner, browser_key: key)
    assert_includes conversation.history, exchange
    assert_equal legacy.id, exchange.reload.conversation_id
    assert_equal "old-thread", legacy.reload.runtime_thread_id
    assert_nil unknown.reload.learner_profile_id
    assert legacy.legacy?
    assert_nil conversation.runtime_thread_id
  end

  test "removing a lesson does not remove its saved conversation" do
    lesson = lessons(:pitch)
    legacy = lesson.conversations.create!(browser_key: SecureRandom.hex(32))
    exchange = legacy.ask!(question: "Keep this", request_key: SecureRandom.uuid, locale: "en")
    lesson.destroy!
    assert_nil legacy.reload.lesson_id
    assert_equal "Keep this", exchange.reload.question
  end
end
