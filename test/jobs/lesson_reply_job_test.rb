require "test_helper"
require_relative "../support/fake_tutor"

class LessonReplyJobTest < ActiveSupport::TestCase
  setup do
    @settings = Rails.configuration.x.local_ai
    @previous_enabled, @previous_adapter = @settings.enabled, @settings.adapter
    @settings.enabled = true
    @settings.adapter = @tutor = FakeTutor.new
    @conversation = lessons(:pitch).conversations.create!(browser_key: SecureRandom.hex(32))
    @exchange = @conversation.ask!(question: "Explain pitch", request_key: SecureRandom.uuid, locale: "en")
  end

  teardown do
    @settings.enabled, @settings.adapter = @previous_enabled, @previous_adapter
  end

  test "disabling AI after enqueue prevents the runtime call" do
    @settings.enabled = false
    LessonReplyJob.perform_now(@exchange)
    assert_equal "disabled", @exchange.reload.error_code
    assert_empty @tutor.calls
  end

  test "a duplicate job does not generate a second answer" do
    2.times { LessonReplyJob.perform_now(@exchange) }
    assert_equal 1, @tutor.calls.length
  end

  test "a running cancellation cannot be overwritten by a late answer" do
    exchange = @exchange
    @tutor.define_singleton_method(:reply) do |*args, **options|
      exchange.cancel!
      "A late answer"
    end
    LessonReplyJob.perform_now(@exchange)
    assert @exchange.reload.cancelled?
    assert_nil @exchange.answer
  end

  test "the database enforces only one pending reply per conversation" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Exchange.transaction(requires_new: true) do
        Exchange.insert_all!([ @exchange.attributes.except("id").merge("request_key" => SecureRandom.uuid) ])
      end
    end
  end
end
