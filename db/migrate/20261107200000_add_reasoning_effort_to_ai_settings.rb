class AddReasoningEffortToAiSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_settings, :reasoning_effort, :string
  end
end
