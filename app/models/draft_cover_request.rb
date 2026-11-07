class DraftCoverRequest < ApplicationRecord
  include DurableDispatch
  include AiConfigured
  belongs_to :course
  belongs_to :exchange
  belongs_to :course_change, optional: true
  enum :status, %w[queued running recovering completed failed cancelled uncertain].index_with(&:itself)
  scope :pending, -> { where(status: %w[queued running recovering]) }
  validates :prompt, presence: true, length: { maximum: 2000 }
  after_create_commit :enqueue

  def pending? = queued? || running? || recovering?
  private def inherited_ai_configuration = exchange.ai_configuration.presence || super
  def enqueue = dispatch_job!(DraftCoverJob)
  def cancelled_by_exchange? = exchange.reload.cancel_requested_at && exchange.cancel_requested_at >= created_at

  def complete!(upload)
    Drafts::Access.synchronize(course) do
      with_lock do
        return unless pending? && !queued?
        if cancelled_by_exchange?
          update!(status: :cancelled)
          return
        end
        unless expires_at&.future?
          update!(status: :failed, error_code: "timeout")
          return
        end
        Drafts::Access.ensure_available!(course, exchange: exchange, cover_request: self)
        unless course.revision == expected_revision
          raise Drafts::Error.new("revision_conflict", "The draft changed while its cover was being generated.")
        end
        change, = CourseChange.record!(course: course, exchange: exchange, operation: "replace_cover") do
          course.cover = upload.attributes
        end
        update!(status: :completed, course_change: change, error_code: nil)
      end
    end
  end

  def fail!(code, state: :failed)
    with_lock { update!(status: state, error_code: code) if pending? }
  end

  def cancel!
    with_lock { update!(status: :cancelled) if pending? }
  end

  def retry!
    Drafts::Access.synchronize(course) do
      Drafts::Access.ensure_available!(course)
      raise Drafts::Error.new("invalid_state", "Only a stopped image request can be retried.") unless failed? || uncertain? || cancelled?
      course.draft_cover_requests.create!(exchange: exchange, prompt: prompt, expected_revision: course.revision)
    end
  end
end
