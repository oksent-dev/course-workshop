require "test_helper"

class CodexConnectionTest < ActiveSupport::TestCase
  test "a missing executable reports an installation error before sending a request" do
    error = assert_raises(LocalAi::Error) do
      Codex::Connection.open(command: [ Rails.root.join("tmp/nonexistent-codex.exe").to_s ]) { flunk "Unexpected connection" }
    end
    assert_equal "runtime_not_found", error.code
  end

  test "stdio transports Unicode and punctuation without shell interpolation" do
    with_fake_server do |connection|
        text = 'Zażółć gęślą jaźń: $(ignored); "hello"'
        assert_equal({ "text" => text }, connection.rpc("echo", text: text))
    end
  end

  test "RPC failures and a closed pipe are mapped to a safe error" do
    %w[fail close].each do |method|
      with_fake_server do |connection|
          error = assert_raises(LocalAi::Error) { connection.rpc(method) }
          assert_equal "unavailable", error.code
      end
    end
  end

  test "cancellation stops a connection and releases its child process" do
    cancelled = false
    with_fake_server(cancelled: -> { cancelled }) do |connection|
        cancelled = true
        assert_raises(LocalAi::Cancelled) { connection.rpc("echo", text: "Stop") }
    end
  end

  private

  def with_fake_server(**options, &block)
    Codex::Connection.open(
      command: [ RbConfig.ruby, Rails.root.join("test/support/fake_app_server.rb").to_s ],
      **options, &block
    )
  end
end
