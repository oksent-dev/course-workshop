class Conversation < ApplicationRecord
  class Busy < StandardError; end

  belongs_to :course
  belongs_to :lesson, optional: true
  belongs_to :learner_profile, optional: true
  has_many :exchanges, -> { order(:id) }, dependent: :destroy

  validates :mode, inclusion: { in: %w[tutor editor] }
  validates :learner_profile, presence: true, unless: :legacy?
  before_validation :set_legacy_course

  def self.for_course!(course:, learner:, browser_key: nil, mode: "tutor")
    learner.with_lock do
      if browser_key.present?
        where(course: course, legacy: true, browser_key: browser_key, learner_profile_id: nil)
          .update_all(learner_profile_id: learner.id)
      end
      find_or_create_by!(course: course, learner_profile: learner, mode: mode, legacy: false)
    end
  end

  def history
    return exchanges if legacy?
    related = self.class.where(course: course, learner_profile: learner_profile, mode: mode)
    Exchange.where(conversation_id: related.select(:id)).order(:id)
  end

  def ask!(question:, request_key:, locale:, selected_text: nil, lesson: self.lesson)
    with_lock do
      existing = exchanges.find_by(request_key: request_key)
      return existing if existing
      raise Busy if history.pending.exists?
      raise ArgumentError, "Lesson must belong to the conversation's course" if lesson && lesson.course_id != course_id

      exchanges.create!(
        question: question.to_s.strip, request_key: request_key, locale: locale,
        lesson_context: {
          course_id: course.id, course: course.title, description: course.description,
          revision: course.revision, mode: mode,
          outline: course.lessons.outline.map { |entry| { id: entry.id, position: entry.position, title: entry.title } },
          lesson_id: lesson&.id, title: lesson&.title,
          language: course.language, body: lesson&.body,
          generation: mode == "editor" ? course.course_generation&.slice(:topic, :status, :plan, :step) : nil,
          selected_text: selected_text.to_s.strip.presence
        }
      )
    end
  end

  def expire_stale!
    history.pending.where(updated_at: ...1.minute.ago).find_each(&:recover_later!)
  end

  private

  def set_legacy_course
    self.course ||= lesson&.course
    self.legacy = true if browser_key.present? && learner_profile_id.nil?
  end
end
