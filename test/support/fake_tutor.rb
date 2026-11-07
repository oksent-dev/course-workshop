class FakeTutor
  attr_reader :calls
  attr_accessor :error, :answer

  def initialize
    @calls = []
    @answer = "A high note has a higher frequency."
  end

  def reply(exchange, on_thread:, cancelled:, run: nil)
    @calls << {
      question: exchange.question, context: exchange.lesson_context,
      locale: exchange.locale, thread_id: exchange.conversation.reload.runtime_thread_id
    }
    raise LocalAi::Error, error if error
    on_thread.call(calls.last[:thread_id] || "fake-thread-#{exchange.conversation_id}")
    raise LocalAi::Cancelled if cancelled.call
    answer
  end
end
