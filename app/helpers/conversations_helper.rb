module ConversationsHelper
  def assistant_page_context
    return unless @course && LocalAi.available?(request)
    return if @course.draft? && !LocalAuthoring.available?(request)

    mode = AssistantContext.mode(@course)
    {
      key: "course-assistant:#{current_learner_profile.id}:#{@course.id}:#{mode}",
      mode: mode, lesson_id: @lesson&.id, revision: @course.revision,
      version: AssistantContext.version(@course),
      label: @lesson&.title || t("courses.outline"),
      title: @course.title, language: @course.language,
      url: course_conversation_path(@course, mode: mode),
      exchanges_url: course_conversation_exchanges_path(@course, mode: mode)
    }
  end
end
