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
      position = { type: "integer", minimum: 1, maximum: CourseGeneration::MAX_LESSONS }
      [
        tool("get_authoring_guide", "Read content formats and the generation workflow.", {}, [], { guide: { type: "string" } }),
        tool("read_generation", "Read this generation's topic, immutable plan, draft and saved lesson IDs.", {}, [],
          { topic: { type: "string" }, lesson_count: { type: [ "integer", "null" ] }, stage: { type: "string" }, current_position: { type: [ "integer", "null" ] }, plan_approved: { type: "boolean" }, plan: { type: "array", items: title }, categories: { type: "array", items: Server::CATEGORY }, course: Server::COURSE, lessons: { type: "array", items: Server::LESSON } }),
        tool("plan_course", "Set metadata and the ordered lesson titles once. On retry, preserve the existing plan.",
          { request_key: Server::REQUEST_KEY, title: title, description: Server::METADATA[:description], category: Server::METADATA[:category], category_id: Server::ID,
            lesson_titles: { type: "array", items: title, minItems: 1, maxItems: CourseGeneration::MAX_LESSONS, uniqueItems: true } },
          %w[request_key title description lesson_titles], { course: Server::COURSE, plan: { type: "array", items: title } }, write: true),
        tool("read_generated_lesson", "Read one saved lesson by its plan position.", { position: position }, %w[position], { lesson: Server::LESSON }),
        tool("save_generated_lesson", "Save the current approved lesson, preserving its ID on retry. Use 250–450 words, an example, an exercise and a meaningful visual. For a generated illustration, provide both illustration_prompt and illustration_alt.",
          { request_key: Server::REQUEST_KEY, position: position, body: { type: "string", minLength: 200, maxLength: 38_000 },
            illustration_prompt: { type: "string", minLength: 1, maxLength: 2_000 }, illustration_alt: { type: "string", minLength: 1, maxLength: 500 } },
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
        { guide: "#{Server::GUIDE}\nRails reserved this draft. Read generation state. During planning choose an appropriate lesson count (1–60), save plan_course once, then stop for human approval. During writing save only current_position from the approved plan, then stop. Other positions and unapproved lesson writes are rejected. Every lesson needs a useful table, math block, Mermaid diagram or attached image in its main material. Alternatively, supply illustration_prompt and illustration_alt with save_generated_lesson; Rails generates and appends the illustration next. Do not add its image reference yourself. No course IDs or expected_revision are accepted. Each write needs a UUID request_key. Preserve saved plans and lessons on retry. Read existing lessons for continuity. Never claim unsaved work is complete." }
      when "read_generation"
        { topic: generation.topic, lesson_count: generation.lesson_count, stage: generation.stage, current_position: generation.current_position,
          plan_approved: generation.plan_approved_at.present?, plan: generation.plan, categories: Category.catalog,
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

    def plan(generation, course, title:, description:, lesson_titles:, category: nil, category_id: nil)
      raise Drafts::Error.new("wrong_stage", "Planning is not active.") unless generation.stage == "planning"
      raise Drafts::Error.new("plan_exists", "A plan already exists. Read and preserve it.") if generation.plan.any?
      unless (1..CourseGeneration::MAX_LESSONS).cover?(lesson_titles.size) && lesson_titles.all?(&:present?) && lesson_titles.uniq.size == lesson_titles.size
        raise Drafts::Error.new("invalid_plan", "Provide 1–60 distinct, nonempty lesson titles appropriate for the topic.")
      end
      course.assign_attributes(title: title, description: description, category: Category.resolve!(category: category, category_id: category_id))
      generation.update!(plan: lesson_titles, lesson_count: lesson_titles.size, activity: "plan_ready", activity_at: Time.current)
      { plan: generation.plan }
    end

    def save_lesson(generation, course, position:, body:, illustration_prompt: nil, illustration_alt: nil)
      unless generation.stage == "writing" && generation.plan_approved_at && position == generation.current_position
        raise Drafts::Error.new("wrong_stage", "Only the current lesson in the approved plan can be written.")
      end
      title = generation.plan[position - 1]
      raise Drafts::Error.new("invalid_plan", "Set a plan first and use a position within it.") unless title
      lesson = course.lessons.find_or_initialize_by(position: position)
      if illustration_prompt.present? != illustration_alt.present? || [ illustration_prompt, illustration_alt ].compact.any? { |text| text.include?("\0") || text.blank? }
        raise Drafts::Error.new("invalid_content", "An illustration request needs both a useful brief and alternative text.")
      end
      Drafts::LessonContent.validate!(body, lesson: lesson, require_visual: illustration_prompt.nil?)
      lesson.update!(title: title, body: body)
      generation.update!(activity: "saved", activity_at: Time.current, illustration_prompt: illustration_prompt, illustration_alt: illustration_alt)
      { lesson: Drafts::Catalog.lesson(lesson, body: true) }
    end

    def response(result, error: false)
      MCP::Tool::Response.new([ { type: "text", text: JSON.generate(result) } ], structured_content: result, error: error)
    end
  end
end
