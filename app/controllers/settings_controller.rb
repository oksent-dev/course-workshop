class SettingsController < ApplicationController
  include LearnerContext
  before_action :require_local_ai

  def show
    if DemoMode.enabled?
      @settings = AiSetting.new
      @models = [ { "id" => @settings.model, "name" => @settings.model_label,
        "reasoning_efforts" => [ @settings.reasoning_effort ].compact,
        "default_reasoning_effort" => @settings.reasoning_effort } ]
      return
    end
    @settings = AiSetting.current
    load_models
  end

  def update
    @settings = AiSetting.current
    input = params.require(:ai_setting).permit(:model, :reasoning_effort, :style_instructions, :lock_version)
    previous = @settings.attributes.slice("model", "reasoning_effort")
    @settings.assign_attributes(input)
    load_models
    selected = @models.find { |model| model["id"] == @settings.model }
    if selected && !input.key?(:reasoning_effort) && (@settings.model != previous["model"] || @settings.reasoning_effort.nil? || selected.fetch("reasoning_efforts").empty?)
      @settings.reasoning_effort = selected["default_reasoning_effort"]
    end
    if !selected && @settings.attributes.slice("model", "reasoning_effort") != previous
      @error = t("settings.model_unavailable")
    elsif selected && !supported_reasoning?(selected)
      @error = t("settings.reasoning_unavailable")
    elsif input[:lock_version].blank?
      @error = t("settings.conflict")
    else
      @settings.model_label = selected["name"] if selected
      return redirect_to settings_path, status: :see_other, notice: t("settings.saved") if @settings.save
      @error = t("settings.invalid")
    end
    render :show, status: :unprocessable_content
  rescue ActiveRecord::StaleObjectError
    @settings.lock_version = AiSetting.current.lock_version
    @error = t("settings.conflict")
    render :show, status: :conflict
  end

  private

  def supported_reasoning?(model)
    choices = model.fetch("reasoning_efforts")
    choices.empty? ? @settings.reasoning_effort.nil? : choices.include?(@settings.reasoning_effort)
  end

  def require_local_ai
    return if DemoMode.enabled? && action_name == "show"
    head :not_found unless LocalAi.available?(request)
  end

  def load_models
    @models = LocalAi.model_catalog.models
    @catalog_unavailable = @models.empty?
  rescue LocalAi::Error
    @models = []
    @catalog_unavailable = true
  end
end
