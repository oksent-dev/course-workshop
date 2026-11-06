module LocalGeneration
  def self.enabled?
    LocalAi.enabled? && LocalAuthoring.enabled?
  end

  def self.available?(request)
    LocalAi.available?(request) && LocalAuthoring.available?(request)
  end

  def self.adapter
    Rails.configuration.x.local_ai.generator || Codex::CourseGenerator.new
  end
end
