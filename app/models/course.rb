class Course < ApplicationRecord
  belongs_to :category
  has_many :lessons, -> { order(:position) }, inverse_of: :course, dependent: :destroy

  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :title, :description, presence: true
  validates :language, format: { with: /\A[a-z]{2,3}\z/ }

  def to_param
    slug
  end
end
