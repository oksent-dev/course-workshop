module Codex
  class History
    def initialize(connection: Connection)
      @connection = connection
    end

    def turn_for(run)
      return unless run.thread_id?
      @connection.open(timeout: 30) do |connection|
        cursor = nil
        100.times do
          page = connection.rpc("thread/turns/list", threadId: run.thread_id,
            limit: 50, itemsView: "full", sortDirection: "desc", cursor: cursor)
          matches = page.fetch("data").select do |turn|
            run.turn_id? ? turn["id"] == run.turn_id : submitted_by?(turn, run)
          end
          raise LocalAi::Error, "uncertain" if matches.size > 1
          return matches.first if matches.one?
          cursor = page["nextCursor"]
          return unless cursor
        end
        raise LocalAi::Error, "history_unavailable"
      end
    end

    def self.answer(turn)
      items = turn.fetch("items", []).select do |item|
        item["type"] == "agentMessage" && [ nil, "final_answer" ].include?(item["phase"])
      end.uniq { |item| item.fetch("id") }
      [ items.map { |item| item.fetch("text") }.join("\n\n").strip, items.map { |item| item.fetch("id") } ]
    end

    private

    def submitted_by?(turn, run)
      turn.fetch("items", []).any? do |item|
        item["type"] == "userMessage" && item.fetch("content", []).any? do |part|
          next false unless part["type"] == "text"
          payload = JSON.parse(part.fetch("text"))
          payload.is_a?(Hash) && payload["app_request_id"] == run.id.to_s
        rescue JSON::ParserError, TypeError
          false
        end
      end
    end
  end
end
