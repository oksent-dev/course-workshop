class Category < ApplicationRecord
  has_many :courses, -> { order(:title, :id) }, inverse_of: :category, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
end
