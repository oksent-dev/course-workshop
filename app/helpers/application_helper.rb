module ApplicationHelper
  def course_progress_action(progress)
    if progress.complete?
      t("learning_progress.review")
    elsif progress.started?
      t("learning_progress.resume")
    else
      t("courses.start")
    end
  end

  def course_language_label(course)
    language_name = t("courses.languages.#{course.language}", default: course.language)
    t("courses.content_language", language: language_name)
  end
end
