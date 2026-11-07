module Drafts
  class AssistantEditor
    def initialize(exchange, token:)
      @exchange, @course, @token = exchange, exchange.conversation.course, token
    end

    def call(name, arguments)
      Access.synchronize(@course) do
        Access.authorize!(@exchange, @token)
        if %w[get_authoring_guide read_draft read_lesson].include?(name)
          return read(name, arguments)
        end
        key = arguments.fetch(:request_key)
        DraftOperation.perform!(request_key: key, operation: name, arguments: arguments.except(:request_key).merge(exchange_id: @exchange.id)) do
          Access.ensure_available!(@course, exchange: @exchange, allow_plan: true) unless name == "refresh_course_view"
          unless arguments[:expected_revision] == @course.revision
            raise Error.new("revision_conflict", "Read the latest draft before applying this change.")
          end
          mutate(name, arguments.except(:request_key, :expected_revision))
        end
      end
    end

    private

    def read(name, args)
      case name
      when "get_authoring_guide"
        { guide: CourseMcp::Server::GUIDE + "\nThe general guide above describes the external authoring server. This scoped editor additionally supports recoverable lesson removal, cover replacement requests, and undo of its latest saved changes. It cannot publish or read another course. Every new or rewritten lesson needs a meaningful visual. Retain existing image references. Read the current course revision before each edit. Plan revisions are allowed only before lessons are written and require fresh human approval. Request the cover last; further writes wait until it finishes. Never claim an image is saved while it is queued. Refresh requests only notify the view; they do not execute JavaScript." }
      when "read_draft"
        undoable = CourseChange.latest_undoable(@course)
        { course: Catalog.course(@course), lessons: @course.lessons.map { |entry| Catalog.lesson(entry) },
          categories: Category.catalog, generation: @course.course_generation&.slice(:topic, :status, :plan, :approved_plan),
          undoable_change_id: undoable&.exchange&.conversation_id == @exchange.conversation_id ? undoable.id : nil,
          changes: @course.course_changes.order(revision: :desc).limit(10).map { |change| change.slice(:id, :operation, :revision, :undone_at) } }
      when "read_lesson"
        lesson = @course.lessons.find(args.fetch(:lesson_id))
        { course: Catalog.course(@course), lesson: Catalog.lesson(lesson, body: true),
          images: lesson.lesson_images.map { |image| image.slice(:key, :alt_text) } }
      end
    end

    def mutate(name, args)
      case name
      when "refresh_course_view"
        return { revision: @course.revision, refresh_requested: true }
      when "request_cover"
        Access.ensure_available!(@course, exchange: @exchange)
        request = @course.draft_cover_requests.create!(exchange: @exchange, prompt: args.fetch(:prompt), expected_revision: @course.revision)
        return { revision: @course.revision, cover_request_id: request.id, status: request.status }
      when "undo_change"
        change = @course.course_changes.joins(:exchange).where(exchanges: { conversation_id: @exchange.conversation_id }).find(args.fetch(:change_id))
        undone = change.undo!(expected_revision: @course.revision, actor: @exchange, allow_active_actor: true)
        return { course: Catalog.course(@course.reload), change_id: undone.id }
      end
      change, result = CourseChange.record!(course: @course, exchange: @exchange, operation: name) do
        case name
        when "update_draft"
          @course.assign_attributes(args.slice(:title, :description))
          @course.category = Category.resolve!(**args.slice(:category, :category_id)) if args.key?(:category) || args.key?(:category_id)
          {}
        when "revise_plan"
          revise_plan(args.fetch(:lesson_titles))
        when "save_lesson"
          Access.ensure_available!(@course, exchange: @exchange)
          lesson = args[:lesson_id] ? @course.lessons.find(args[:lesson_id]) : @course.lessons.build(position: (@course.lessons.maximum(:position) || 0) + 1)
          raise Error.new("invalid_content", "A course supports at most 60 lessons.") if lesson.new_record? && @course.lessons.count >= 60
          LessonContent.validate!(args.fetch(:body), lesson: lesson, require_visual: true)
          lesson.update!(args.slice(:title, :body))
          { lesson: Catalog.lesson(lesson) }
        when "remove_lesson"
          Access.ensure_available!(@course, exchange: @exchange)
          lesson = @course.lessons.find(args.fetch(:lesson_id))
          lesson.update!(archived_at: Time.current)
          LessonOrder.apply!(@course, @course.lessons.reload.ids)
          { lesson_id: lesson.id }
        when "reorder_lessons"
          Access.ensure_available!(@course, exchange: @exchange)
          LessonOrder.apply!(@course, args.fetch(:lesson_ids))
          { lesson_ids: args[:lesson_ids] }
        else
          raise Error.new("unknown_tool", "Unknown draft operation.")
        end
      end
      result.merge(course: Catalog.course(@course), change_id: change.id)
    end

    def revise_plan(titles)
      generation = @course.course_generation
      unless generation && !generation.pending? && !generation.completed? && @course.lessons.empty? &&
          (1..60).cover?(titles.size) && titles.uniq.size == titles.size && titles.all? { |title| title.present? && title.length <= 160 }
        raise Error.new("invalid_plan", "Revise the plan before lessons are written, using 1–60 distinct titles.")
      end
      generation.update!(plan: titles, lesson_count: titles.size, plan_approved_at: nil, status: :awaiting_approval,
        stage: "planning", current_position: nil, token_digest: nil, error_code: nil, attempt: generation.attempt + 1,
        step: generation.step + 1, activity: "plan_ready", activity_at: Time.current)
      { plan: titles, approval_required: true }
    end
  end
end
