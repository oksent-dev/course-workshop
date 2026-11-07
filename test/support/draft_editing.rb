module DraftEditing
  BODY = <<~MARKDOWN.freeze
    ## A useful explanation
    Compare the observations before making a decision. The table connects each observation
    to an example so the learner can apply the idea in everyday situations.

    | Observation | Example |
    | --- | --- |
    | A regular pattern | A daily commute |
    | An exception | A delayed train |

    ## Practice
    Describe one pattern and an exception from your own experience, and explain the difference.
  MARKDOWN

  def start_editor(course = courses(:listening))
    course.update!(status: :draft)
    learner = LearnerProfile.create!(key: SecureRandom.hex(32))
    conversation = Conversation.for_course!(course: course, learner: learner, mode: "editor")
    exchange = conversation.ask!(question: "Improve this draft", request_key: SecureRandom.uuid, locale: "en")
    activate_editor(exchange)
    exchange
  end

  def activate_editor(exchange)
    @token = SecureRandom.hex(32)
    exchange.update!(status: :running, editor_token_digest: Digest::SHA256.hexdigest(@token), editor_expires_at: 7.minutes.from_now)
  end

  def edit(exchange, name, **arguments)
    Drafts::AssistantEditor.new(exchange, token: @token).call(name,
      { request_key: SecureRandom.uuid, expected_revision: exchange.conversation.course.reload.revision }.merge(arguments))
  end
end
