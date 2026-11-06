module Codex
  module Runtime
    def self.verify(connection)
      account = connection.rpc("account/read", refreshToken: false)
      raise LocalAi::Error, "authentication" if account["requiresOpenaiAuth"] && account["account"].nil?

      cursor = nil
      loop do
        models = connection.rpc("model/list", limit: 100, includeHidden: true, cursor: cursor)
        return if models.fetch("data").any? { |model| model["model"] == LocalAi::MODEL }
        cursor = models["nextCursor"]
        break unless cursor
      end
      raise LocalAi::Error, "model_unavailable"
    end

    def self.restricted_config(connection)
      config = connection.rpc("config/read", includeLayers: false).fetch("config")
      overrides = {
        "project_doc_max_bytes" => 0,
        "skills.include_instructions" => false,
        "skills.bundled.enabled" => false,
        "web_search" => "disabled",
        "plugins._default.enabled" => false
      }
      %w[shell_tool unified_exec view_image apps plugins remote_plugin memories hooks multi_agent goals js_repl computer_use browser_use].each do |feature|
        overrides["features.#{feature}"] = false
      end
      %w[mcp_servers plugins].each do |section|
        config.fetch(section, {}).each_key do |name|
          overrides["#{section}.#{name}.enabled"] = false
        end
      end
      overrides
    end
  end
end
