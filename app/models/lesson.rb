class Lesson < ApplicationRecord
  has_many :conversations, dependent: :destroy
  has_many :lesson_images, dependent: :destroy
  has_many :lesson_progresses, dependent: :destroy
  belongs_to :course

  scope :outline, -> { select(:id, :course_id, :position, :title) }

  validates :title, :body, presence: true
  validates :title, length: { maximum: 160 }
  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :course_id }
end
