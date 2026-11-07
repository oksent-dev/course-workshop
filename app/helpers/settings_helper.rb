module SettingsHelper
  def reasoning_model_options(models)
    models.to_h do |model|
      [ model["id"], {
        options: model.fetch("reasoning_efforts").map { |effort| [ reasoning_label(effort), effort ] },
        preferred: model["default_reasoning_effort"]
      } ]
    end
  end

  def reasoning_label(effort)
    t("settings.reasoning_levels.#{effort}", default: effort.humanize)
  end

  def reasoning_selection(model, settings)
    return settings.reasoning_effort unless model
    model.fetch("reasoning_efforts").include?(settings.reasoning_effort) ? settings.reasoning_effort : model["default_reasoning_effort"]
  end

  def reasoning_select_options(model, settings)
    if model
      options = model.fetch("reasoning_efforts").map { |effort| [ reasoning_label(effort), effort ] }
      options.presence || [ [ t("settings.reasoning_not_configurable"), "" ] ]
    else
      [ [ settings.reasoning_effort.present? ? reasoning_label(settings.reasoning_effort) : t("settings.reasoning_saved"), settings.reasoning_effort ] ]
    end
  end
end
