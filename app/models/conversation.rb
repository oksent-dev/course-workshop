class Conversation < ApplicationRecord
  class Busy < StandardError; end

  belongs_to :lesson
  has_many :exchanges, -> { order(:id) }, dependent: :destroy

  validates :browser_key, presence: true

  def ask!(question:, request_key:, locale:, selected_text: nil)
    with_lock do
      existing = exchanges.find_by(request_key: request_key)
      return existing if existing
      raise Busy if exchanges.pending.exists?

      exchanges.create!(
        question: question.to_s.strip, request_key: request_key, locale: locale,
        lesson_context: {
          course: lesson.course.title, title: lesson.title,
          language: lesson.course.language, body: lesson.body,
          selected_text: selected_text.to_s.strip.presence
        }
      )
    end
  end

  def expire_stale!
    exchanges.pending.where(created_at: ...5.minutes.ago).find_each do |exchange|
      exchange.with_lock do
        exchange.update!(status: :failed, error_code: "timeout") if exchange.pending?
      end
    end
  end
end
