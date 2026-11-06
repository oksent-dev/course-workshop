module ApplicationHelper
  def language_switch_path(locale)
    options = request.path_parameters.merge(locale: locale)
    options[:category] = params[:category] if controller_name == "pages" && action_name == "home" && params[:category].present?
    url_for(options)
  end

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
