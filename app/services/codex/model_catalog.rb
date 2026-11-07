module Codex
  class ModelCatalog
    def initialize(connection: Connection)
      @connection = connection
    end

    def models
      @connection.open(timeout: 10) do |connection|
        Runtime.models(connection).filter_map do |entry|
          next if entry["hidden"] && entry["model"] != LocalAi::DEFAULT_MODEL
          next unless entry.fetch("inputModalities", [ "text" ]).include?("text")
          id = entry["model"]
          next unless id.is_a?(String) && id.length <= 120 && id.match?(/\A[a-zA-Z0-9._:\/-]+\z/)
          { "id" => id, "name" => entry["displayName"].presence&.truncate(160) || id,
            "reasoning_efforts" => Runtime.reasoning_choices(entry), "default_reasoning_effort" => Runtime.default_reasoning_effort(entry) }
        end.uniq { |entry| entry["id"] }.sort_by { |entry| [ entry["id"] == LocalAi::DEFAULT_MODEL ? 0 : 1, entry["name"] ] }
      end
    end
  end
end
