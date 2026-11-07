class AddAiPreferencesAndProvenance < ActiveRecord::Migration[8.1]
  def up
    create_table :ai_settings do |t|
      t.string :key, null: false, default: "local"
      t.string :model, null: false, default: "gpt-6.1-sol"
      t.string :model_label, null: false, default: "GPT-6.1 Sol"
      t.text :style_instructions, null: false, default: ""
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :ai_settings, :key, unique: true
    add_check_constraint :ai_settings, "key = 'local'", name: "ai_settings_local_only"
    configuration = { provider: "codex", model: "gpt-6.1-sol", model_name: "GPT-6.1 Sol", style_instructions: "" }.to_json
    %i[course_generations exchanges course_cover_generations draft_cover_requests ai_runs].each do |table|
      add_column table, :ai_configuration, :jsonb, null: false, default: {}
      execute "UPDATE #{table} SET ai_configuration = #{connection.quote(configuration)}::jsonb"
    end
    add_column :courses, :generation_provider, :string
    add_column :courses, :generation_model, :string
    add_column :courses, :generation_model_name, :string
    execute <<~SQL
      UPDATE courses SET generation_provider = 'codex', generation_model = 'gpt-6.1-sol', generation_model_name = 'GPT-6.1 Sol'
      WHERE id IN (SELECT course_id FROM course_generations)
    SQL
  end

  def down
    %i[generation_provider generation_model generation_model_name].each { |column| remove_column :courses, column }
    %i[course_generations exchanges course_cover_generations draft_cover_requests ai_runs].each { |table| remove_column table, :ai_configuration }
    drop_table :ai_settings
  end
end
