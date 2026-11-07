require "mcp"

module CourseMcp
  class EditorServer
    TOOL_NAMES = %w[get_authoring_guide read_draft read_lesson update_draft save_lesson remove_lesson reorder_lessons revise_plan request_cover undo_change refresh_course_view].freeze

    def initialize(exchange_id:, token:)
      @exchange_id, @token = exchange_id, token
    end

    def build
      MCP::Server.new(name: "course_editor", version: "0.1.0", tools: tools,
        instructions: "Edit only this draft. Read its current revision before each write. Preserve existing work. Never publish.",
        configuration: MCP::Configuration.new(validate_tool_call_results: true,
          exception_reporter: ->(error, _) { Rails.logger.error("Editor MCP failed (#{error.class.name})") }))
    end

    def execute(name, arguments)
      activity = nil
      Rails.application.executor.wrap do
        exchange = Exchange.find(@exchange_id)
        Drafts::Access.authorize!(exchange, @token)
        raise Drafts::Error.new("unknown_tool", "Unknown editor tool.") unless TOOL_NAMES.include?(name)
        activity = exchange.assistant_activities.find_or_create_by!(key: arguments[:request_key] || SecureRandom.uuid) { |row| row.tool = name }
        result = Drafts::AssistantEditor.new(exchange, token: @token).call(name, arguments)
        activity.update!(status: :completed, error_code: nil, course_change_id: result[:change_id] || result["change_id"])
        response(result)
      end
    rescue Drafts::Error => error
      activity&.update!(status: :failed, error_code: error.code) unless activity&.course_change_id?
      response({ code: error.code, message: error.message }, error: true)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => error
      code = error.is_a?(ActiveRecord::RecordNotFound) ? "not_found" : "invalid_content"
      activity&.update!(status: :failed, error_code: code)
      response({ code: code, message: "The requested draft material is missing or invalid. Read the draft again." }, error: true)
    end

    private

    def tools
      mutation = { request_key: Server::REQUEST_KEY, expected_revision: Server::REVISION }
      definitions = [
        [ "get_authoring_guide", "Read the supported learning formats and editing rules.", {}, [] ],
        [ "read_draft", "Read this draft, current revision, categories, outline and recent change IDs.", {}, [] ],
        [ "read_lesson", "Read a lesson and its existing image keys from this draft.", { lesson_id: Server::ID }, %w[lesson_id] ],
        [ "update_draft", "Change only supplied draft metadata. Reuse an existing category where suitable.", mutation.merge(Server::METADATA.except(:language)), %w[request_key expected_revision] ],
        [ "save_lesson", "Replace a lesson's complete title and body, or append a new lesson without lesson_id. Include a useful visual, example and exercise. Preserve attached image references.", mutation.merge(lesson_id: Server::ID, title: Server::TITLE, body: { type: "string", minLength: 200, maxLength: 40_000 }), %w[request_key expected_revision title body] ],
        [ "remove_lesson", "Archive a lesson recoverably and close the gap in the outline.", mutation.merge(lesson_id: Server::ID), %w[request_key expected_revision lesson_id] ],
        [ "reorder_lessons", "Set the order using every current lesson ID exactly once.", mutation.merge(lesson_ids: { type: "array", items: Server::ID, uniqueItems: true, maxItems: 60 }), %w[request_key expected_revision lesson_ids] ],
        [ "revise_plan", "Replace the initial plan before any lesson is written. Requires fresh human approval; cannot modify a running or completed generation plan.", mutation.merge(lesson_titles: { type: "array", items: Server::TITLE, minItems: 1, maxItems: 60, uniqueItems: true }), %w[request_key expected_revision lesson_titles] ],
        [ "request_cover", "Queue a new cover using a visual brief. The existing cover stays until replacement succeeds. Request last: writes wait for the image job. Never claim the queued image is already saved.", mutation.merge(prompt: { type: "string", minLength: 1, maxLength: 2000 }), %w[request_key expected_revision prompt] ],
        [ "undo_change", "Undo the latest eligible change from this conversation, without overwriting later edits.", mutation.merge(change_id: Server::ID), %w[request_key expected_revision change_id] ],
        [ "refresh_course_view", "Notify the browser that this saved revision is ready to display. No URL or script is accepted; the browser may defer while the learner is composing.", mutation, %w[request_key expected_revision] ]
      ]
      definitions.map do |name, description, properties, required|
        handler = self
        MCP::Tool.define(name: name, description: description,
          input_schema: { type: "object", properties: properties, required: required, additionalProperties: false },
          output_schema: { type: "object", additionalProperties: true },
          annotations: { read_only_hint: !properties.key?(:request_key), destructive_hint: properties.key?(:request_key), idempotent_hint: true, open_world_hint: false }
        ) { |server_context: nil, **arguments| handler.execute(name, arguments) }
      end
    end

    def response(result, error: false)
      MCP::Tool::Response.new([ { type: "text", text: JSON.generate(result) } ], structured_content: result, error: error)
    end
  end
end
