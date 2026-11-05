class CreateCourseLibrary < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :name, null: false, index: { unique: true }
      t.timestamps
    end

    create_table :courses do |t|
      t.references :category, null: false, foreign_key: true
      t.string :slug, null: false, index: { unique: true }
      t.string :title, null: false
      t.text :description, null: false
      t.string :language, null: false
      t.timestamps
    end

    create_table :lessons do |t|
      t.references :course, null: false, foreign_key: true, index: false
      t.integer :position, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.timestamps

      t.index [ :course_id, :position ], unique: true
      t.check_constraint "position > 0", name: "lessons_positive_position"
    end
  end
end
