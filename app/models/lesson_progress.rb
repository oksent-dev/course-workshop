class LessonProgress < ApplicationRecord
  belongs_to :learner_profile
  belongs_to :lesson

  validates :last_opened_at, presence: true

  def complete!
    with_lock { update!(completed_at: Time.current) unless completed_at? }
  end
end
