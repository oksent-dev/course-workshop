class AiSetting < ApplicationRecord
  validates :key, inclusion: { in: [ "local" ] }
  validates :model, format: { with: /\A[a-zA-Z0-9._:\/-]+\z/ }, length: { maximum: 120 }
  validates :model_label, presence: true, length: { maximum: 160 }
  validates :reasoning_effort, format: { with: /\A[a-z0-9_-]+\z/ }, length: { maximum: 40 }, allow_nil: true
  normalizes :reasoning_effort, with: ->(value) { value.presence }
  validates :style_instructions, length: { maximum: 1000 }, format: { without: /\x00/ }
  normalizes :style_instructions, with: ->(value) { value.to_s.strip }

  def self.current
    find_or_create_by!(key: "local")
  end

  def snapshot
    { "provider" => "codex", "model" => model, "model_name" => model_label,
      "reasoning_effort" => reasoning_effort, "style_instructions" => style_instructions }
  end
end
