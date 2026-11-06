class LearnerProfile < ApplicationRecord
  has_many :lesson_progresses, dependent: :destroy

  validates :key, format: { with: /\A(?:local|[a-f0-9]{64})\z/ }

  def progress_for(lesson)
    lesson_progresses.find_or_create_by!(lesson: lesson) do |progress|
      progress.last_opened_at = Time.current
    end
  end
end
