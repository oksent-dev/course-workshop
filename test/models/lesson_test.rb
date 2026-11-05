require "test_helper"

class LessonTest < ActiveSupport::TestCase
  test "PostgreSQL enforces a positive unique position within an existing course" do
    attributes = lessons(:pitch).attributes.symbolize_keys.slice(:course_id, :position, :title, :body)

    assert_raises(ActiveRecord::RecordNotUnique) do
      Lesson.transaction(requires_new: true) { Lesson.insert!(attributes) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      Lesson.transaction(requires_new: true) { Lesson.insert!(attributes.merge(position: 0)) }
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Lesson.transaction(requires_new: true) { Lesson.insert!(attributes.merge(course_id: -1)) }
    end

    other_lesson = courses(:composition).lessons.create!(attributes.except(:course_id))
    assert_equal lessons(:pitch).position, other_lesson.position
  end
end
