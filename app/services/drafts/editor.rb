module Drafts
  class Editor
    MAX_LESSONS = 60

    def self.create_course(slug:, title:, description:, language:, category: nil, category_id: nil)
      record = Course.create!(slug: slug, title: title, description: description, language: language,
        category: Category.resolve!(category: category, category_id: category_id), status: "draft")
      { course: Catalog.course(record) }
    end

    def self.update_course(course_id:, expected_revision:, title:, description:, language:, category: nil, category_id: nil)
      change(course_id, expected_revision) do |course|
        course.assign_attributes(title: title, description: description, language: language,
          category: Category.resolve!(category: category, category_id: category_id))
        {}
      end
    end

    def self.save_lesson(course_id:, expected_revision:, title:, body:, lesson_id: nil)
      change(course_id, expected_revision) do |course|
        if lesson_id
          lesson = course.lessons.find(lesson_id)
        else
          raise Error.new("invalid_content", "A course supports at most 60 lessons.") if course.lessons.count >= MAX_LESSONS
          lesson = course.lessons.build(position: (course.lessons.maximum(:position) || 0) + 1)
        end
        LessonContent.validate!(body, lesson: lesson)
        lesson.update!(title: title, body: body)
        { lesson: Catalog.lesson(lesson, body: true) }
      end
    end

    def self.reorder_lessons(course_id:, expected_revision:, lesson_ids:)
      change(course_id, expected_revision) do |course|
        lessons = course.lessons.to_a
        unless lesson_ids.sort == lessons.map(&:id).sort && lesson_ids.uniq == lesson_ids
          raise Error.new("invalid_order", "lesson_ids must include every lesson in this course exactly once.")
        end
        offset = (lessons.map(&:position).max || 0) + lessons.size + 1
        course.lessons.update_all([ "position = position + ?", offset ])
        by_id = lessons.index_by(&:id)
        lesson_ids.each_with_index { |id, index| by_id.fetch(id).update_columns(position: index + 1, updated_at: Time.current) }
        { lesson_ids: lesson_ids }
      end
    end

    def self.publish(course_id:, expected_revision:)
      change(course_id, expected_revision) do |course|
        lessons = course.lessons.to_a
        if lessons.empty? || lessons.map(&:position) != (1..lessons.size).to_a
          raise Error.new("invalid_content", "A course needs lessons in consecutive order before approval.")
        end
        lessons.each { |lesson| LessonContent.validate!(lesson.body, lesson: lesson) }
        course.status = "published"
        {}
      end
    end

    def self.change(course_id, expected_revision)
      course = Course.find(course_id)
      course.with_lock do
        raise Error.new("not_draft", "Only draft courses can be changed.") unless course.draft?
        if course.course_generation && !course.course_generation.completed?
          raise Error.new("generation_incomplete", "Finish course generation before editing or approving this draft.")
        end
        unless course.revision == expected_revision
          raise Error.new("revision_conflict", "The course changed. Read its latest revision before retrying with a new request_key.")
        end
        result = yield course
        course.revision += 1
        course.save!
        result.merge(course: Catalog.course(course))
      end
    end

    private_class_method :change
  end
end
