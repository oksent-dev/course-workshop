require "mcp"

module CourseMcp
  class GenerationServer
    TOOL_NAMES = %w[get_authoring_guide read_generation plan_course read_generated_lesson save_generated_lesson].freeze

    def initialize(generation_id:, token:)
      @generation_id, @token = generation_id, token
    end

    def build
      MCP::Server.new(name: "course_generation", version: "0.1.0", tools: tools,
        instructions: "Read the guide and generation state first. Write only this reserved draft. Keep its saved plan and lesson positions when resuming. Never publish.",
        configuration: MCP::Configuration.new(validate_tool_call_results: true,
          exception_reporter: ->(error, _) { Rails.logger.error("Generation MCP failed (#{error.class.name})") }))
    end

    def execute(name, arguments, write:)
      Rails.application.executor.wrap do
        raise Drafts::Error.new("disabled", "Local generation is disabled.") unless LocalGeneration.enabled?
        generation = CourseGeneration.find(@generation_id)
        generation.with_lock do
          generation.authorize!(@token)
          result = if write
            key = arguments.delete(:request_key)
            DraftOperation.perform!(request_key: key, operation: name, arguments: arguments.merge(generation_id: generation.id)) do
              perform(generation, name, arguments)
            end
          else
            perform(generation, name, arguments)
          end
          response(result)
        end
      end
    rescue Drafts::Error => error
      response({ code: error.code, message: error.message }, error: true)
    rescue ActiveRecord::RecordNotFound
      response({ code: "not_found", message: "The generation or lesson was not found." }, error: true)
    rescue ActiveRecord::RecordInvalid
      response({ code: "invalid_content", message: "Course metadata or lesson content is invalid." }, error: true)
    end

    private

    def tools
      title = Server::TITLE
      position = { type: "integer", minimum: 1, maximum: 6 }
      [
        tool("get_authoring_guide", "Read content formats and the generation workflow.", {}, [], { guide: { type: "string" } }),
        tool("read_generation", "Read this generation's topic, immutable plan, draft and saved lesson IDs.", {}, [],
          { topic: { type: "string" }, lesson_count: position, plan: { type: "array", items: title }, course: Server::COURSE, lessons: { type: "array", items: Server::LESSON } }),
        tool("plan_course", "Set metadata and the ordered lesson titles once. On retry, preserve the existing plan.",
          { request_key: Server::REQUEST_KEY, title: title, description: Server::METADATA[:description], category: Server::METADATA[:category],
            lesson_titles: { type: "array", items: title, minItems: 3, maxItems: 6, uniqueItems: true } },
          %w[request_key title description category lesson_titles], { course: Server::COURSE, plan: { type: "array", items: title } }, write: true),
        tool("read_generated_lesson", "Read one saved lesson by its plan position.", { position: position }, %w[position], { lesson: Server::LESSON }),
        tool("save_generated_lesson", "Save a complete lesson at a planned position, preserving its ID on retry. Use 250–450 words, an example and an exercise.",
          { request_key: Server::REQUEST_KEY, position: position, body: { type: "string", minLength: 200, maxLength: 40_000 } },
          %w[request_key position body], { lesson: Server::LESSON, course: Server::COURSE }, write: true)
      ]
    end

    def tool(name, description, properties, required, output, write: false)
      handler = self
      MCP::Tool.define(name: name, description: description,
        input_schema: { type: "object", properties: properties, required: required, additionalProperties: false },
        output_schema: { type: "object", properties: output, required: output.keys.map(&:to_s), additionalProperties: false },
        annotations: { read_only_hint: !write, destructive_hint: write, idempotent_hint: true, open_world_hint: false }
      ) { |server_context: nil, **arguments| handler.execute(name, arguments, write: write) }
    end

    def perform(generation, name, arguments)
      course = generation.course
      case name
      when "get_authoring_guide"
        { guide: "#{Server::GUIDE}\nFor this scoped server, Rails already reserved the course. Read generation state, set plan_course exactly once, then save_generated_lesson by position. No course IDs or expected_revision are accepted. Each write needs a UUID request_key. Preserve the plan and existing lessons on retry. Use read_generated_lesson to review saved material. Include a practice exercise in every lesson. Never include placeholder content or claim unsaved work is complete." }
      when "read_generation"
        { topic: generation.topic, lesson_count: generation.lesson_count, plan: generation.plan,
          course: Drafts::Catalog.course(course), lessons: course.lessons.map { |lesson| Drafts::Catalog.lesson(lesson) } }
      when "read_generated_lesson"
        { lesson: Drafts::Catalog.lesson(course.lessons.find_by!(position: arguments.fetch(:position)), body: true) }
      else
        course.with_lock do
          raise Drafts::Error.new("not_draft", "Only this draft can be changed.") unless course.draft?
          result = name == "plan_course" ? plan(generation, course, **arguments) : save_lesson(generation, course, **arguments)
          course.increment(:revision).save!
          result.merge(course: Drafts::Catalog.course(course))
        end
      end
    end

    def plan(generation, course, title:, description:, category:, lesson_titles:)
      raise Drafts::Error.new("plan_exists", "A plan already exists. Read and preserve it.") if generation.plan.any?
      unless lesson_titles.size == generation.lesson_count && lesson_titles.all?(&:present?)
        raise Drafts::Error.new("invalid_plan", "Provide exactly the requested number of nonempty lesson titles.")
      end
      course.assign_attributes(title: title, description: description, category: Category.find_or_create_by!(name: category))
      generation.update!(plan: lesson_titles)
      { plan: generation.plan }
    end

    def save_lesson(generation, course, position:, body:)
      title = generation.plan[position - 1]
      raise Drafts::Error.new("invalid_plan", "Set a plan first and use a position within it.") unless title
      lesson = course.lessons.find_or_initialize_by(position: position)
      Drafts::LessonContent.validate!(body, lesson: lesson)
      lesson.update!(title: title, body: body)
      { lesson: Drafts::Catalog.lesson(lesson, body: true) }
    end

    def response(result, error: false)
      MCP::Tool::Response.new([ { type: "text", text: JSON.generate(result) } ], structured_content: result, error: error)
    end
  end
end
