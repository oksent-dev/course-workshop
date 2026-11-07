module Drafts
  class Snapshot
    METADATA = %w[title description language category_id].freeze
    LESSON = %w[id title body position].freeze
    PLAN = %w[plan lesson_count plan_approved_at approved_plan status stage current_position].freeze

    def self.capture(course)
      {
        "metadata" => course.attributes.slice(*METADATA),
        "lessons" => course.lessons.reload.map { |lesson| lesson.attributes.slice(*LESSON) },
        "cover_blob_id" => course.cover_attachment&.reload&.blob_id,
        "generation" => course.course_generation&.reload&.attributes&.slice(*PLAN)
      }.as_json
    end

    def self.restore!(course, state)
      course.assign_attributes(state.fetch("metadata"))
      course.lessons.update_all(archived_at: Time.current)
      state.fetch("lessons").each do |attributes|
        lesson = course.all_lessons.find(attributes.fetch("id"))
        lesson.update!(attributes.except("id").merge("archived_at" => nil))
      end
      if state["cover_blob_id"] != course.cover_attachment&.blob_id
        course.cover = state["cover_blob_id"] ? ActiveStorage::Blob.find(state["cover_blob_id"]) : nil
      end
      if state["generation"]
        course.course_generation.update!(state["generation"].merge("token_digest" => nil))
      end
    end
  end
end
