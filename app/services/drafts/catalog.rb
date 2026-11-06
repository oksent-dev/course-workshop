module Drafts
  class Catalog
    def self.course(course)
      course.attributes.slice("id", "slug", "title", "description", "language", "status", "revision")
        .merge("category" => course.category.name)
    end

    def self.lesson(lesson, body: false)
      result = lesson.attributes.slice("id", "course_id", "title", "position")
      result["body"] = lesson.body if body
      result
    end

    def self.list(status: "all", after_id: 0, limit: 20)
      scope = Course.where("id > ?", after_id).order(:id).includes(:category)
      scope = scope.where(status: status) unless status == "all"
      rows = scope.limit(limit + 1).to_a
      { courses: rows.first(limit).map { |row| course(row) }, next_after_id: rows.size > limit ? rows[limit - 1].id : nil }
    end

    def self.read(course_id:)
      record = Course.find(course_id)
      record.with_lock do
        { course: course(record), lessons: record.lessons.outline.map { |row| lesson(row) } }
      end
    end

    def self.read_lesson(course_id:, lesson_id:)
      record = Course.find(course_id)
      record.with_lock do
        row = record.lessons.find(lesson_id)
        { course: course(record), lesson: lesson(row, body: true),
          images: row.lesson_images.order(:key).map { |image| { key: image.key, alt_text: image.alt_text } } }
      end
    end
  end
end
