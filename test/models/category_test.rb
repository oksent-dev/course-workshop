require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  test "names are normalized and existing categories are reused without changing their label" do
    category = Category.create!(name: "  Data   science ")
    assert_equal "Data science", category.name
    assert_no_difference "Category.count" do
      assert_equal category, Category.resolve!(category: " data SCIENCE ")
      assert_equal category, Category.resolve!(category_id: category.id)
    end
    assert_equal "Data science", category.reload.name
    assert_raises(ActiveRecord::RecordInvalid) { Category.create!(name: "DATA SCIENCE") }
    assert_raises(ActiveRecord::RecordNotUnique) do
      Category.transaction(requires_new: true) do
        Category.insert_all!([ { name: "DATA SCIENCE", created_at: Time.current, updated_at: Time.current } ])
      end
    end
  end

  test "category selection is exclusive and the placeholder is excluded" do
    placeholder = Category.create!(name: "Drafts")
    assert_not_includes Category.catalog.map { |row| row[:id] }, placeholder.id
    assert_raises(Drafts::Error) { Category.resolve! }
    assert_raises(Drafts::Error) { Category.resolve!(category_id: categories(:music).id, category: "Other") }
    assert_raises(Drafts::Error) { Category.resolve!(category: " drafts ") }
    assert_raises(ActiveRecord::RecordNotFound) { Category.resolve!(category_id: placeholder.id) }
    assert_raises(ActiveRecord::RecordNotFound) { Category.resolve!(category_id: 0) }
  end
end
