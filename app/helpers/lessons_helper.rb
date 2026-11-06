module LessonsHelper
  def render_lesson_body(lesson)
    LessonMarkdown.new(lesson, view: self).render
  end
end
