module LocalAi
  DEFAULT_MODEL = "gpt-6.1-sol"
  TIMEOUT = 180

  class Error < StandardError
    attr_reader :code

    def initialize(code = "unavailable")
      @code = code
      super(code)
    end
  end

  class Cancelled < StandardError; end

  def self.enabled?
    !DemoMode.enabled? && (Rails.env.development? || Rails.env.test?) && Rails.configuration.x.local_ai.enabled == true
  end

  def self.available?(request)
    enabled? && [ "127.0.0.1", "::1" ].include?(request.remote_ip) &&
      [ "localhost", "127.0.0.1", "::1", "[::1]" ].include?(request.host)
  end

  def self.adapter
    Rails.configuration.x.local_ai.adapter || Codex::Tutor.new
  end

  def self.editor_adapter
    Rails.configuration.x.local_ai.editor || Codex::Editor.new
  end

  def self.model_catalog
    Rails.configuration.x.local_ai.model_catalog || Codex::ModelCatalog.new
  end
end
