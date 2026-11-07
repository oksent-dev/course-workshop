module Drafts
  class LessonOrder
    def self.apply!(course, ids)
      lessons = course.lessons.reload.to_a
      unless ids.sort == lessons.map(&:id).sort && ids.uniq == ids
        raise Error.new("invalid_order", "Include every current lesson ID exactly once.")
      end
      offset = (lessons.map(&:position).max || 0) + lessons.size + 1
      course.lessons.update_all([ "position = position + ?", offset ])
      by_id = lessons.index_by(&:id)
      ids.each_with_index { |id, index| by_id.fetch(id).update_columns(position: index + 1, updated_at: Time.current) }
    end
  end
end
