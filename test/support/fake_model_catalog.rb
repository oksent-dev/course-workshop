class FakeModelCatalog
  attr_accessor :unavailable

  def models
    raise LocalAi::Error, "unavailable" if unavailable
    [ { "id" => LocalAi::DEFAULT_MODEL, "name" => "GPT-6.1 Sol", "reasoning_efforts" => %w[low medium high], "default_reasoning_effort" => "low" },
      { "id" => "test-model", "name" => "Test model", "reasoning_efforts" => %w[medium high], "default_reasoning_effort" => "medium" },
      { "id" => "fixed-model", "name" => "Fixed reasoning model", "reasoning_efforts" => [], "default_reasoning_effort" => nil } ]
  end
end
