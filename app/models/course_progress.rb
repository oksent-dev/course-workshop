class CourseProgress
  attr_reader :lessons

  def self.for_lessons(profile, lessons)
    new(lessons, profile.lesson_progresses.where(lesson_id: lessons.map(&:id)).index_by(&:lesson_id))
  end

  def self.for_courses(profile, courses)
    lessons = Lesson.outline.where(course_id: courses.map(&:id)).order(:position, :id).to_a
    records = profile.lesson_progresses.where(lesson_id: lessons.map(&:id)).index_by(&:lesson_id)
    by_course = lessons.group_by(&:course_id)
    courses.to_h { |course| [ course.id, new(by_course.fetch(course.id, []), records) ] }
  end

  def initialize(lessons, records)
    @lessons = lessons
    @records = records.slice(*lessons.map(&:id))
  end

  def total = lessons.size
  def completed_count = @records.values.count(&:completed_at?)
  def started? = @records.any?
  def complete? = total.positive? && completed_count == total
  def completed?(lesson) = @records[lesson.id]&.completed_at? || false

  def resume_lesson
    return lessons.first unless started? && !complete?

    latest = @records.values.max_by { |record| [ record.last_opened_at, record.id ] }
    index = lessons.index { |lesson| lesson.id == latest.lesson_id }
    lessons.drop(index).find { |lesson| !completed?(lesson) } || lessons.find { |lesson| !completed?(lesson) }
  end
end
