class CreateLessonImages < ActiveRecord::Migration[8.1]
  def change
    create_table :lesson_images do |t|
      t.references :lesson, null: false, foreign_key: true, index: false
      t.string :key, null: false
      t.text :alt_text, null: false
      t.timestamps
    end
    add_index :lesson_images, [ :lesson_id, :key ], unique: true
  end
end
