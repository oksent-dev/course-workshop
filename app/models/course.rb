class Course < ApplicationRecord
  belongs_to :category
  has_many :lessons, -> { where(archived_at: nil).order(:position) }, inverse_of: :course
  has_many :all_lessons, class_name: "Lesson", dependent: :destroy
  has_many :course_changes, dependent: :destroy
  has_many :draft_cover_requests, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_one :course_generation, dependent: :destroy
  has_one :cover_generation, class_name: "CourseCoverGeneration", dependent: :destroy
  has_one_attached :cover do |attachment|
    attachment.variant :card, resize_to_fill: [ 960, 540 ], format: :webp, saver: { quality: 82 }
  end

  enum :status, { draft: "draft", published: "published" }, validate: true
  validates :revision, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :title, length: { maximum: 160 }
  validates :description, length: { maximum: 2_000 }
  validates :slug, length: { maximum: 80 }

  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :title, :description, presence: true
  validates :language, format: { with: /\A[a-z]{2,3}\z/ }
  validate :acceptable_cover

  def to_param
    slug
  end

  private

  def acceptable_cover
    return unless cover.attached?

    errors.add(:cover, "must be PNG, JPEG, or WebP") unless ImageUpload::CONTENT_TYPES.include?(cover.blob.content_type)
    errors.add(:cover, "must be at most 5 MB") if cover.blob.byte_size > ImageUpload::MAX_BYTES
  end
end
