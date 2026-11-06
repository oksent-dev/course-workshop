class Course < ApplicationRecord
  belongs_to :category
  has_many :lessons, -> { order(:position) }, inverse_of: :course, dependent: :destroy
  has_one :course_generation, dependent: :destroy

  enum :status, { draft: "draft", published: "published" }, validate: true
  validates :revision, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :title, length: { maximum: 160 }
  validates :description, length: { maximum: 2_000 }
  validates :slug, length: { maximum: 80 }

  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :title, :description, presence: true
  validates :language, format: { with: /\A[a-z]{2,3}\z/ }

  def to_param
    slug
  end
end
