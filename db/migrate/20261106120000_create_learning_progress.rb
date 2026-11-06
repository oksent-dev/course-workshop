class CreateLearningProgress < ActiveRecord::Migration[8.1]
  def change
    create_table :learner_profiles do |t|
      t.string :key, null: false
      t.timestamps
      t.index :key, unique: true
    end

    create_table :lesson_progresses do |t|
      t.references :learner_profile, null: false, foreign_key: true, index: false
      t.references :lesson, null: false, foreign_key: true
      t.datetime :last_opened_at, null: false
      t.datetime :completed_at
      t.timestamps
      t.index [ :learner_profile_id, :lesson_id ], unique: true
    end
  end
end
