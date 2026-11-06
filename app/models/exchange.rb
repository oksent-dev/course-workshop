class Exchange < ApplicationRecord
  belongs_to :conversation

  enum :status, %w[queued running completed failed cancelled].index_with(&:itself)
  scope :pending, -> { where(status: %w[queued running]) }

  validates :question, presence: true, length: { maximum: 4000 }
  validates :request_key, format: { with: /\A[0-9a-f-]{36}\z/ }, uniqueness: { scope: :conversation_id }
  validates :locale, inclusion: { in: %w[pl en] }
  validates :lesson_context, presence: true

  def pending?
    queued? || running?
  end

  def cancel!
    with_lock do
      if queued?
        update!(status: :cancelled)
      elsif running?
        update!(cancel_requested_at: Time.current)
      end
    end
  end
end
