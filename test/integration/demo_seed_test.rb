require "test_helper"

class DemoSeedTest < ActiveSupport::TestCase
  test "reloading the demo preserves record identities and other courses" do
    Rails.application.load_seed
    course = Course.find_by!(slug: "statystyka-na-co-dzien")
    lesson_ids = course.lessons.ids
    assert_equal [ 1, 2, 3 ], course.lessons.pluck(:position)

    assert_no_difference [ "Category.count", "Course.count", "Lesson.count" ] do
      Rails.application.load_seed
    end

    assert_equal lesson_ids, course.reload.lessons.ids
    assert_equal "Listening closely", courses(:listening).reload.title
  end
end
