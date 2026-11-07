module Drafts
  class Access
    def self.synchronize(course, &block)
      generation = course.course_generation
      if generation
        generation.with_lock { course.with_lock(&block) }
      else
        course.with_lock(&block)
      end
    end

    def self.ensure_available!(course, exchange: nil, cover_request: nil, allow_plan: false)
      raise Error.new("not_draft", "Only drafts can be changed.") unless course.draft?
      ensure_no_editor!(course, exchange: exchange)
      covers = course.draft_cover_requests.pending
      covers = covers.where.not(id: cover_request.id) if cover_request
      if covers.exists? || course.cover_generation&.pending?
        raise Error.new("cover_busy", "Wait for the cover or cancel its replacement before changing this draft.")
      end
      generation = course.course_generation&.reload
      return unless generation && !generation.completed?
      return if allow_plan && !generation.pending? && course.lessons.empty?
      code = generation.pending? ? "generation_busy" : "generation_incomplete"
      raise Error.new(code, "Finish generation before editing lessons. A plan can be revised before any lessons are written.")
    end

    def self.ensure_no_editor!(course, exchange: nil)
      pending = Exchange.pending.joins(:conversation).where(conversations: { course_id: course.id, mode: "editor" })
      pending = pending.where.not(id: exchange.id) if exchange
      raise Error.new("editor_busy", "Another editing request is still active.") if pending.exists?
    end

    def self.authorize!(exchange, token)
      unless LocalGeneration.enabled? && exchange.conversation.mode == "editor" && exchange.conversation.course.draft? && exchange.reload.running? &&
          !exchange.cancel_requested_at? && exchange.editor_expires_at&.future? && exchange.editor_token_digest.present? &&
          ActiveSupport::SecurityUtils.secure_compare(exchange.editor_token_digest, Digest::SHA256.hexdigest(token.to_s))
        raise Error.new("inactive_editor", "This editing run no longer has write access.")
      end
    end
  end
end
