class FakeCourseGenerator
  BODY = <<~MARKDOWN.freeze
    ## A practical example

    A course has many lessons. Give each lesson a course identifier and an ordered position.
    Validate the relationship before saving and use database constraints to protect concurrent writes.
    Consider how a missing parent should be handled before changing records. Compare application
    validations with database constraints and explain which layer protects each invariant.

    ```exercise
    {"prompt":"Which record owns the course identifier?","answer":"The lesson owns the course identifier because it belongs to a course."}
    ```
  MARKDOWN

  attr_reader :calls
  attr_accessor :fail_after, :before_finish

  def initialize
    @calls = []
  end

  def generate(generation, token:, cancelled:)
    @calls << generation.id
    server = CourseMcp::GenerationServer.new(generation_id: generation.id, token: token).build
    unless generation.reload.plan.any?
      self.class.call(server, "plan_course", request_key: SecureRandom.uuid, title: "Active Record essentials",
        description: "Practical associations and validations.", category: "Programming",
        lesson_titles: (1..generation.lesson_count).map { |number| "Lesson #{number}" })
    end
    (1..generation.lesson_count).each do |position|
      next if generation.course.lessons.exists?(position: position)
      self.class.call(server, "save_generated_lesson", request_key: SecureRandom.uuid, position: position, body: BODY)
      raise LocalAi::Error, "unavailable" if fail_after == position
    end
    before_finish&.call(generation, server)
  end

  def self.call(server, name, **arguments)
    response = JSON.parse(server.handle_json(JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments }))).fetch("result")
    raise "Unexpected tool error: #{response}" if response["isError"]
    response.fetch("structuredContent")
  end
end
