class LessonImage < ApplicationRecord
  CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  MAX_BYTES = 5.megabytes
  MAX_PIXELS = 20_000_000

  belongs_to :lesson
  has_one_attached :file

  validates :key, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }, length: { maximum: 80 },
    uniqueness: { scope: :lesson_id }
  validates :alt_text, presence: true, length: { maximum: 500 }
  validate :acceptable_file

  private

  def acceptable_file
    if !file.attached?
      errors.add(:file, "must be attached")
    elsif !CONTENT_TYPES.include?(file.blob.content_type)
      errors.add(:file, "must be PNG, JPEG, or WebP")
    elsif file.blob.byte_size > MAX_BYTES
      errors.add(:file, "must be at most 5 MB")
    end
  end
end
