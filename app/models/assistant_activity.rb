class AssistantActivity < ApplicationRecord
  belongs_to :exchange
  belongs_to :course_change, optional: true
  enum :status, %w[running completed failed].index_with(&:itself)

  def reconcile!
    return if course_change_id?
    receipt = DraftOperation.find_by(request_key: key)
    change = exchange.course_changes.find_by(id: receipt&.result&.fetch("change_id", nil))
    if change
      update!(status: :completed, course_change: change, error_code: nil)
    elsif receipt&.result.present?
      update!(status: :completed, error_code: nil)
    elsif running? && !exchange.pending?
      update!(status: :failed, error_code: "interrupted")
    end
  end
end
