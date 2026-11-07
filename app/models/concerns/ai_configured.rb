module AiConfigured
  extend ActiveSupport::Concern

  included do
    before_validation :capture_ai_configuration, on: :create
    attr_readonly :ai_configuration
  end

  def ai_model = ai_configuration.fetch("model", LocalAi::DEFAULT_MODEL)

  private

  def capture_ai_configuration
    self.ai_configuration = inherited_ai_configuration.deep_dup if ai_configuration.blank?
  end

  def inherited_ai_configuration = AiSetting.current.snapshot
end
