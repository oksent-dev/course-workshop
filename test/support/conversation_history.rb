module ConversationHistory
  def saved_exchanges(conversation, count)
    Array.new(count) do |index|
      conversation.exchanges.create!(
        question: "Saved question #{index + 1}", answer: "Saved answer #{index + 1}. " * 8,
        locale: "en", status: :completed, request_key: SecureRandom.uuid,
        lesson_context: { course: conversation.course.title, mode: conversation.mode }
      )
    end
  end
end
