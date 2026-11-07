module Codex
  class RpcError < LocalAi::Error
    attr_reader :rpc_code

    def initialize(error)
      @rpc_code = error["code"]
      @detail = error["message"].to_s
      super("unavailable")
    end

    def missing_thread?
      @detail.match?(/(?:thread|session).*(?:not found|does not exist)|no (?:rollout|thread) found/i)
    end
  end
end
