require "test_helper"

class LocalAiTest < ActiveSupport::TestCase
  test "production cannot enable the local runtime" do
    previous_environment = Rails.env
    previous_enabled = Rails.configuration.x.local_ai.enabled
    Rails.configuration.x.local_ai.enabled = true
    Rails.env = "production"

    assert_not LocalAi.enabled?
  ensure
    Rails.env = previous_environment
    Rails.configuration.x.local_ai.enabled = previous_enabled
  end
end
