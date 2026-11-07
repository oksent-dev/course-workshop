class CourseCoverGeneration < ApplicationRecord
  include DurableDispatch
  include AiConfigured
  TIMEOUT = 300
  EXPIRY = 7.minutes

  belongs_to :course
  enum :status, %w[queued running completed failed].index_with(&:itself)
  after_create_commit :enqueue

  def pending?
    queued? || running?
  end

  private def inherited_ai_configuration
    course.course_generation&.ai_configuration.presence || super
  end

  def enqueue
    dispatch_job!(CourseCoverGenerationJob) { [ attempt ] }
  end

  def claim!(expected_attempt)
    with_lock do
      return false unless queued? && attempt == expected_attempt
      update!(status: :running, expires_at: EXPIRY.from_now)
    end
  end

  def complete!(expected_attempt, upload:)
    with_lock do
      return unless running? && attempt == expected_attempt && expires_at.future?
      course.with_lock do
        unless course.cover.attached?
          course.cover = upload.attributes
          course.save!
        end
        update!(status: :completed, error_code: nil)
      end
    end
  end

  def fail!(expected_attempt, code)
    with_lock do
      update!(status: :failed, error_code: code) if pending? && attempt == expected_attempt
    end
  end

  def expire_stale!
    if (run = ai_runs.active.find_by(operation_key: attempt.to_s))
      AiRecoveryJob.perform_later(run) if run.recoverable_now?
      return
    end
    with_lock do
      update!(status: :failed, error_code: "timeout") if running? && expires_at.past?
    end
  end

  def retry!(expected_attempt)
    with_lock do
      return false unless failed? && attempt == expected_attempt
      course.with_lock do
        Drafts::Access.ensure_no_editor!(course)
        raise Drafts::Error.new("cover_busy", "A replacement cover is pending.") if course.draft_cover_requests.pending.exists?
        update!(status: :queued, attempt: attempt + 1, error_code: nil,
          enqueued_job_id: nil, enqueued_at: nil, expires_at: EXPIRY.from_now)
      end
    end
  end
end
