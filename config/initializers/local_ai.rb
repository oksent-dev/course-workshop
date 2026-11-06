Rails.application.config.x.local_ai.enabled = ENV["LOCAL_AI_ENABLED"] == "true"
Rails.application.config.x.local_ai.executable = ENV.fetch("CODEX_EXECUTABLE", "codex")
