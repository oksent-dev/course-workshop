class LessonImage < ApplicationRecord
  CONTENT_TYPES = ImageUpload::CONTENT_TYPES
  MAX_BYTES = ImageUpload::MAX_BYTES
  MAX_PIXELS = ImageUpload::MAX_PIXELS

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
