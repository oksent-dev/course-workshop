module ApplicationHelper
  def course_language_label(course)
    language_name = t("courses.languages.#{course.language}", default: course.language)
    t("courses.content_language", language: language_name)
  end
end
