ENV["RAILS_ENV"] ||= "test"
ENV["LOCAL_AI_ENABLED"] = "false"
ENV["COURSE_AUTHORING_ENABLED"] = "false"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/fake_cover_generator"

module ActiveSupport
  class TestCase
    fixtures :all

    setup do
      @previous_cover_generator = Rails.configuration.x.local_ai.cover_generator
      @previous_illustrator = Rails.configuration.x.local_ai.illustrator
      Rails.configuration.x.local_ai.cover_generator = FakeCoverGenerator.new
      Rails.configuration.x.local_ai.illustrator = FakeCoverGenerator.new
    end

    teardown do
      Rails.configuration.x.local_ai.cover_generator = @previous_cover_generator
      Rails.configuration.x.local_ai.illustrator = @previous_illustrator
      ActiveStorage::Attachment.find_each(&:purge)
    end
  end
end
