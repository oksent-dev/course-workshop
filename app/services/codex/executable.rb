module Codex
  class Executable
    def self.resolve(configured, windows: Gem.win_platform?, local_app_data: ENV["LOCALAPPDATA"])
      return configured unless configured == "codex-desktop"
      raise LocalAi::Error, "runtime_not_found" unless windows && local_app_data.present?

      directory = File.join(local_app_data.tr("\\", "/"), "OpenAI", "Codex", "bin")
      candidates = Dir.glob(File.join(directory, "*", "codex.exe")).select do |path|
        File.file?(path) && File.basename(File.dirname(path)).match?(/\A[0-9a-f]+\z/i)
      end
      candidates.max_by { |path| [ File.mtime(path), path ] } || raise(LocalAi::Error, "runtime_not_found")
    end
  end
end
