require "digest"

class CourseGeneration < ApplicationRecord
  TIMEOUT = 600
  EXPIRY = 12.minutes

  belongs_to :course
  enum :status, %w[queued running completed failed cancelled].index_with(&:itself)
  validates :topic, presence: true, length: { maximum: 2_000 }, format: { without: /\x00/ }
  validates :language, inclusion: { in: %w[pl en] }
  validates :lesson_count, inclusion: { in: 3..6 }
  validates :request_key, format: { with: /\A[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z/ }

  def self.submit!(topic: nil, language: nil, lesson_count: nil, request_key: nil)
    input = { topic: topic.to_s.strip, language: language, lesson_count: lesson_count.to_i, request_key: request_key }
    existing = find_by(request_key: request_key)
    return identical_submission!(existing, input) if existing

    transaction do
      course = Course.new(slug: "generated-#{SecureRandom.uuid}", title: input[:topic].truncate(160),
        description: "Draft awaiting generation.", language: language,
        category: Category.find_or_create_by!(name: "Drafts"))
      create!(**input, course: course, expires_at: EXPIRY.from_now)
    end
  rescue ActiveRecord::RecordNotUnique
    existing = find_by(request_key: request_key)
    raise unless existing
    identical_submission!(existing, input)
  end

  def self.identical_submission!(record, input)
    unless record.attributes.slice("topic", "language", "lesson_count") == input.except(:request_key).stringify_keys
      record.errors.add(:request_key, :taken)
      raise ActiveRecord::RecordInvalid, record
    end
    record
  end
  private_class_method :identical_submission!

  def pending?
    queued? || running?
  end

  def claim!(expected_attempt)
    with_lock do
      return unless queued? && attempt == expected_attempt && expires_at.future?
      token = SecureRandom.hex(32)
      update!(status: :running, token_digest: Digest::SHA256.hexdigest(token), expires_at: EXPIRY.from_now)
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
      update!(status: :cancelled, token_digest: nil, error_code: nil) if pending? && attempt == expected_attempt
    end
  end

  def retry!(expected_attempt)
    with_lock do
      return false unless (failed? || cancelled?) && attempt == expected_attempt && course.draft?
      update!(status: :queued, attempt: attempt + 1, error_code: nil, token_digest: nil, expires_at: EXPIRY.from_now)
      true
    end
  end

  def expire_stale!
    with_lock do
      update!(status: :failed, error_code: "timeout", token_digest: nil) if pending? && expires_at.past?
    end
  end

  def finish!(expected_attempt, status:, error_code: nil)
    with_lock do
      return unless pending? && attempt == expected_attempt
      update!(status: status, error_code: error_code, token_digest: nil)
    end
  end

  def complete!(expected_attempt)
    with_lock do
      return unless running? && attempt == expected_attempt
      course.with_lock do
        lessons = course.lessons.to_a
        unless course.draft? && plan.size == lesson_count && lessons.map(&:position) == (1..lesson_count).to_a && lessons.map(&:title) == plan
          raise LocalAi::Error, "incomplete"
        end
        lessons.each do |lesson|
          Drafts::LessonContent.validate!(lesson.body, lesson: lesson)
          raise LocalAi::Error, "incomplete" if lesson.body.length < 200
        end
        update!(status: :completed, token_digest: nil, error_code: nil)
      end
    end
  end
end
