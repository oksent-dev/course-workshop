class Category < ApplicationRecord
  has_many :courses, -> { order(:title, :id) }, inverse_of: :category, dependent: :restrict_with_error
  has_many :published_courses, -> { published.order(:title, :id) }, class_name: "Course"

  normalizes :name, with: ->(name) { name.squish }
  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :name, length: { maximum: 80 }

  def self.for_drafts
    insert_all([ { name: "Drafts" } ], unique_by: :index_categories_on_normalized_name)
    find_by!("LOWER(name) = ?", "drafts")
  end

  def self.catalog
    where.not(name: "Drafts").order(:name, :id).map { |category| { id: category.id, name: category.name } }
  end

  def self.resolve!(category_id: nil, category: nil)
    if category_id.present? == category.present?
      raise Drafts::Error.new("invalid_category", "Provide category_id to reuse a category, or category for a new name, never both.")
    end
    return where.not(name: "Drafts").find(category_id) if category_id

    name = category.to_s.squish
    if name.casecmp?("Drafts")
      raise Drafts::Error.new("invalid_category", "Drafts is reserved for unfinished generations.")
    end
    matching = -> { where("LOWER(name) = LOWER(?)", name).first }
    matching.call || transaction(requires_new: true) { create!(name: name) }
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    matching&.call || raise
  end
end
