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

  def self.cover_adapter
    Rails.configuration.x.local_ai.cover_generator || Codex::CoverGenerator.new
  end

  def self.illustrator
    Rails.configuration.x.local_ai.illustrator || Codex::LessonIllustrator.new
  end
end
