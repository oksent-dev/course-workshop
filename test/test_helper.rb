ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    fixtures :all

    teardown do
      ActiveStorage::Attachment.find_each(&:purge)
    end
  end
end
