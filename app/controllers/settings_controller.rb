class SettingsController < ApplicationController
  include LearnerContext
  before_action :require_local_ai

  def show
    @settings = AiSetting.current
    load_models
  end

  def update
    @settings = AiSetting.current
    input = params.require(:ai_setting).permit(:model, :style_instructions, :lock_version)
    previous_model = @settings.model
    @settings.assign_attributes(input)
    load_models
    selected = @models.find { |model| model["id"] == @settings.model }
    if @settings.model != previous_model && !selected
      @error = t("settings.model_unavailable")
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

  def require_local_ai
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
