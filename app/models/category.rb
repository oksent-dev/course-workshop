class Category < ApplicationRecord
  has_many :courses, -> { order(:title, :id) }, inverse_of: :category, dependent: :restrict_with_error
  has_many :published_courses, -> { published.order(:title, :id) }, class_name: "Course"

  validates :name, presence: true, uniqueness: true
  validates :name, length: { maximum: 80 }
end
