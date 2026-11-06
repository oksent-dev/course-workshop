require "test_helper"

class CourseProgressTest < ActiveSupport::TestCase
  setup do
    @profile = LearnerProfile.create!(key: "local")
    @course = courses(:listening)
    @first, @last = @course.lessons.to_a
  end

  test "opening a lesson does not complete it and resume follows the most recent visit" do
    assert_equal @first, progress.resume_lesson
    assert_not progress.started?
    @profile.progress_for(@last)
    assert_equal @last, progress.resume_lesson
    assert_equal 0, progress.completed_count

    travel 1.minute do
      @profile.progress_for(@first)
      assert_equal @first, progress.resume_lesson
    end
  end

  test "resume skips completed lessons, wraps to unfinished ones, and supports review" do
    @profile.progress_for(@last).complete!
    assert_equal @first, progress.resume_lesson
    @profile.progress_for(@first).complete!
    assert progress.complete?
    assert_equal 2, progress.completed_count
    assert_equal @first, progress.resume_lesson

    @profile.progress_for(@last).update!(completed_at: nil)
    assert_not progress.complete?
    assert_equal @last, progress.resume_lesson
  end

  test "completion is idempotent and PostgreSQL prevents duplicate or orphaned progress" do
    record = @profile.progress_for(@first)
    record.complete!
    timestamp = record.completed_at
    travel 1.minute do
      record.complete!
      assert_equal timestamp, record.reload.completed_at
    end

    attributes = record.attributes.symbolize_keys.except(:id)
    assert_raises(ActiveRecord::RecordNotUnique) do
      LessonProgress.transaction(requires_new: true) { LessonProgress.insert!(attributes) }
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      LessonProgress.transaction(requires_new: true) { LessonProgress.insert!(attributes.merge(lesson_id: -1)) }
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      LessonProgress.transaction(requires_new: true) { LessonProgress.insert!(attributes.merge(learner_profile_id: -1)) }
    end
    assert_raises(ActiveRecord::RecordNotUnique) do
      LearnerProfile.transaction(requires_new: true) { LearnerProfile.insert!({ key: "local" }) }
    end
  end

  test "removing a lesson removes its progress and counts use the current outline" do
    @profile.progress_for(@first).complete!
    @first.destroy!
    assert_equal 1, progress.total
    assert_equal 0, progress.completed_count
    assert_equal 0, @profile.lesson_progresses.count
  end

  test "empty courses have no resume target and are not complete" do
    empty = CourseProgress.for_courses(@profile, [ courses(:composition) ]).fetch(courses(:composition).id)
    assert_nil empty.resume_lesson
    assert_not empty.complete?
    assert_equal 0, empty.total
  end

  private

  def progress
    CourseProgress.for_courses(@profile, [ @course ]).fetch(@course.id)
  end
end
