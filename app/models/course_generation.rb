require "digest"

class CourseGeneration < ApplicationRecord
  include DurableDispatch
  include AiConfigured
  TIMEOUT = 300
  EXPIRY = 7.minutes
  MAX_LESSONS = 60

  belongs_to :course
  enum :status, %w[queued running awaiting_approval completed failed cancelled].index_with(&:itself)
  validates :topic, presence: true, length: { maximum: 2_000 }, format: { without: /\x00/ }
  validates :language, inclusion: { in: %w[pl en] }
  validates :lesson_count, inclusion: { in: 1..MAX_LESSONS }, allow_nil: true
  validates :request_key, format: { with: /\A[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z/ }

  def self.submit!(topic: nil, language: nil, request_key: nil)
    input = { topic: topic.to_s.strip, language: language, request_key: request_key }
    existing = find_by(request_key: request_key)
    return identical_submission!(existing, input) if existing

    transaction do
      configuration = AiSetting.current.snapshot
      course = Course.new(slug: "generated-#{SecureRandom.uuid}", title: input[:topic].truncate(160),
        description: "Draft awaiting generation.", language: language,
        generation_provider: configuration.fetch("provider"), generation_model: configuration.fetch("model"), generation_model_name: configuration.fetch("model_name"),
        generation_reasoning_effort: configuration["reasoning_effort"],
        category: Category.for_drafts)
      create!(**input, course: course, ai_configuration: configuration, expires_at: EXPIRY.from_now)
    end
  rescue ActiveRecord::RecordNotUnique
    existing = find_by(request_key: request_key)
    raise unless existing
    identical_submission!(existing, input)
  end

  def self.identical_submission!(record, input)
    unless record.attributes.slice("topic", "language") == input.except(:request_key).stringify_keys
      record.errors.add(:request_key, :taken)
      raise ActiveRecord::RecordInvalid, record
    end
    record
  end
  private_class_method :identical_submission!

  def pending?
    queued? || running?
  end

  def claim!(expected_attempt, expected_step = step)
    with_lock do
      return unless queued? && attempt == expected_attempt && step == expected_step
      token = SecureRandom.hex(32)
      update!(status: :running, token_digest: Digest::SHA256.hexdigest(token), expires_at: EXPIRY.from_now,
        activity: stage, activity_at: Time.current)
      token
    end
  end

  def authorize!(token)
    unless running? && expires_at.future? && token_digest.present? &&
        ActiveSupport::SecurityUtils.secure_compare(token_digest, Digest::SHA256.hexdigest(token.to_s))
      raise Drafts::Error.new("inactive_generation", "This generation attempt no longer has write access.")
    end
  end

  def cancel!(expected_attempt)
    with_lock do
      update!(status: :cancelled, token_digest: nil, error_code: nil) if (pending? || awaiting_approval?) && attempt == expected_attempt
    end
  end

  def retry!(expected_attempt)
    with_lock do
      return false unless (failed? || cancelled?) && attempt == expected_attempt && course.draft?
      course.with_lock do
        Drafts::Access.ensure_no_editor!(course)
        next_state = plan.any? && !plan_approved_at ? :awaiting_approval : :queued
        update!(status: next_state, attempt: attempt + 1, error_code: nil, token_digest: nil,
          enqueued_job_id: nil, enqueued_at: nil, expires_at: EXPIRY.from_now)
        queue_next_step! if plan_approved_at
        true
      end
    end
  end

  def expire_stale!
    if (run = ai_runs.active.find_by(operation_key: "#{attempt}:#{step}"))
      AiRecoveryJob.perform_later(run) if run.recoverable_now?
      return
    end
    with_lock do
      update!(status: :failed, error_code: "timeout", token_digest: nil) if running? && expires_at.past?
    end
  end

  def finish!(expected_attempt, status:, error_code: nil, expected_step: step)
    with_lock do
      return unless pending? && attempt == expected_attempt && step == expected_step
      update!(status: status, error_code: error_code, token_digest: nil)
    end
  end

  def approve_plan!(expected_attempt, expected_revision)
    with_lock do
      return false unless awaiting_approval? && attempt == expected_attempt
      course.with_lock do
        Drafts::Access.ensure_no_editor!(course)
        return false unless course.draft? && course.revision == expected_revision && plan.any?
        update!(plan_approved_at: Time.current, approved_plan: plan, error_code: nil)
        queue_next_step!
      end
    end
  end

  def advance!(expected_attempt, expected_step)
    with_lock do
      return false unless running? && attempt == expected_attempt && step == expected_step && expires_at.future?
      if stage == "planning"
        raise LocalAi::Error, "incomplete" unless plan.any? && plan.size == lesson_count
        update!(status: :awaiting_approval, token_digest: nil, activity: "plan_ready", activity_at: Time.current)
        false
      elsif stage == "writing"
        lesson = course.lessons.find_by(position: current_position)
        raise LocalAi::Error, "incomplete" unless lesson && lesson.body.length >= 200
        queue_next_step!
      elsif stage == "illustrating"
        raise LocalAi::Error, "incomplete" if illustration_prompt.present?
        queue_next_step!
      else
        complete!(expected_attempt)
        false
      end
    end
  end

  def record_activity!(token, value)
    with_lock do
      authorize!(token)
      update!(activity: value, activity_at: Time.current) if activity != value || activity_at.nil? || activity_at < 15.seconds.ago
    end
  end

  def record_reasoning_effort!(effort)
    return if effort.blank?
    course.with_lock do
      course.update!(generation_reasoning_effort: effort) unless course.generation_reasoning_effort.present?
    end
  end

  def attach_illustration!(expected_attempt, expected_step, upload)
    with_lock do
      return unless running? && stage == "illustrating" && attempt == expected_attempt && step == expected_step && expires_at.future?
      lesson = course.lessons.find_by!(position: current_position)
      lesson.with_lock do
        image = lesson.lesson_images.find_or_initialize_by(key: "generated-illustration")
        image.alt_text = illustration_alt
        image.file = upload.attributes
        image.save!
        alt = illustration_alt.gsub(/[\[\]\\\r\n]/, " ")
        lesson.update!(body: "#{lesson.body}\n\n![#{alt}](image:generated-illustration)\n")
        Drafts::LessonContent.validate!(lesson.body, lesson: lesson, require_visual: true)
        update!(illustration_prompt: nil, illustration_alt: nil, activity: "saved", activity_at: Time.current)
      end
    end
  end

  def complete!(expected_attempt)
    with_lock do
      return unless running? && attempt == expected_attempt && expires_at.future? && plan_approved_at
      course.with_lock do
        lessons = course.lessons.to_a
        unless course.draft? && plan.size == lesson_count && lessons.map(&:position) == (1..lesson_count).to_a && lessons.map(&:title) == plan
          raise LocalAi::Error, "incomplete"
        end
        lessons.each do |lesson|
          Drafts::LessonContent.validate!(lesson.body, lesson: lesson, require_visual: true)
          raise LocalAi::Error, "incomplete" if lesson.body.length < 200
        end
        update!(status: :completed, token_digest: nil, error_code: nil)
        course.update!(generated_at: Time.current) unless course.generated_at?
        course.create_cover_generation!(expires_at: CourseCoverGeneration::EXPIRY.from_now) unless course.cover.attached? || course.cover_generation
      end
    end
  end

  private

  def queue_next_step!
    if illustration_prompt.present?
      update!(status: :queued, stage: "illustrating", step: step + 1, token_digest: nil,
        enqueued_job_id: nil, enqueued_at: nil,
        expires_at: EXPIRY.from_now, activity: "queued", activity_at: Time.current)
      return true
    end
    saved = course.lessons.pluck(:position)
    position = (1..lesson_count).find { |number| !saved.include?(number) }
    update!(status: :queued, stage: position ? "writing" : "checking", current_position: position,
      enqueued_job_id: nil, enqueued_at: nil,
      step: step + 1, token_digest: nil, expires_at: EXPIRY.from_now, activity: "queued", activity_at: Time.current)
    true
  end
end
