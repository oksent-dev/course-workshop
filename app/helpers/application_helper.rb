module ApplicationHelper
  def language_switch_path(locale)
    options = request.path_parameters.merge(locale: locale)
    if ((controller_name == "pages" && action_name == "home") || (controller_name == "drafts" && action_name == "index")) && params[:category].present?
      options[:category] = params[:category]
    end
    options[:lesson_id] = params[:lesson_id] if controller_name == "drafts" && action_name == "show" && params[:lesson_id].present?
    url_for(options)
  end

  def navigation_section
    return :settings if controller_name == "settings"
    return :create if controller_name == "generations" && %w[new create].include?(action_name)
    return :drafts if %w[drafts generations].include?(controller_name)
    :library
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

  def draft_entry_path(course)
    generation = course.course_generation
    if generation && LocalGeneration.available?(request)
      generation_path(generation)
    else
      draft_path(course.id)
    end
  end

  def course_language_label(course)
    language_name = t("courses.languages.#{course.language}", default: course.language)
    t("courses.content_language", language: language_name)
  end

  def draft_editing_busy?(course)
    Exchange.pending.joins(:conversation).where(conversations: { course_id: course.id, mode: "editor" }).exists? ||
      course.draft_cover_requests.pending.exists? || course.cover_generation&.pending?
  end
end
