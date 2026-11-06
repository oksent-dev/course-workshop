require "json"
require "open3"

module Codex
  class Connection
    def self.open(cancelled: -> { false }, **options)
      connection = new(cancelled: cancelled, **options)
      yield connection
    ensure
      connection&.close
    end

    def initialize(cancelled:, command: nil, timeout: LocalAi::TIMEOUT)
      @cancelled = cancelled
      @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      @sequence = 0
      @notifications = []
      @messages = Queue.new
      workspace = Rails.root.join("tmp", "codex-workspace")
      FileUtils.mkdir_p(workspace)
      command ||= [
        Rails.configuration.x.local_ai.executable, "app-server", "--listen", "stdio://",
        "-c", "features.hooks=false"
      ]
      @input, @output, @error, @process = Open3.popen3(*command, chdir: workspace.to_s)
      @input.set_encoding(Encoding::UTF_8)
      @reader = Thread.new do
        @output.each_line { |line| @messages << JSON.parse(line) }
      rescue JSON::ParserError, IOError
        nil
      ensure
        @messages << :closed
      end
      @drainer = Thread.new do
        @error.each_line { |_| }
      rescue IOError
        nil
      end
      rpc("initialize", clientInfo: { name: "course_workshop", title: "Course Workshop", version: "0.1.0" })
      write(method: "initialized")
    rescue StandardError => error
      close
      raise LocalAi::Error, "unavailable" if error.is_a?(SystemCallError) || error.is_a?(IOError)
      raise
    end

    def rpc(method, **params)
      @sequence += 1
      id = @sequence
      write(id: id, method: method, params: params)
      loop do
        message = read_message
        if message["id"] == id
          raise LocalAi::Error, "unavailable" if message["error"]
          return message.fetch("result")
        end
        handle_notification(message)
      end
    end

    def notification
      return @notifications.shift if @notifications.any?
      loop do
        message = read_message
        handle_notification(message)
        return @notifications.shift if @notifications.any?
      end
    end

    def interrupt(thread_id, turn_id)
      write(id: "interrupt", method: "turn/interrupt", params: { threadId: thread_id, turnId: turn_id })
    rescue IOError, SystemCallError
      nil
    end

    def close
      @input&.close unless @input&.closed?
      if @process && !@process.join(2)
        Process.kill("KILL", @process.pid)
        @process.join
      end
    rescue SystemCallError, IOError
      nil
    ensure
      [ @output, @error ].compact.each { |io| io.close unless io.closed? }
      [ @reader, @drainer ].compact.each { |thread| thread.join(1) || thread.kill }
    end

    private

    def write(message)
      @input.puts(JSON.generate(message))
      @input.flush
    end

    def read_message
      loop do
        raise LocalAi::Cancelled if @cancelled.call
        raise LocalAi::Error, "timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline
        message = @messages.pop(timeout: 0.25)
        raise LocalAi::Error, "unavailable" if message == :closed
        return message if message
      end
    end

    def handle_notification(message)
      if message["method"] && message.key?("id")
        write(id: message["id"], error: { code: -32601, message: "Interactive tools are unavailable in this tutor." })
        raise LocalAi::Error, "unsupported_tool"
      elsif message["method"]
        @notifications << message
      end
    end
  end
end
