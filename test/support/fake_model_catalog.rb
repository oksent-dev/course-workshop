class FakeModelCatalog
  attr_accessor :unavailable

  def models
    raise LocalAi::Error, "unavailable" if unavailable
    [ { "id" => LocalAi::DEFAULT_MODEL, "name" => "GPT-6.1 Sol" }, { "id" => "test-model", "name" => "Test model" } ]
  end
end
