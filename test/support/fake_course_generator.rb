class FakeCourseGenerator
  BODY = <<~MARKDOWN.freeze
    ## A practical example

    A course has many lessons. Give each lesson a course identifier and an ordered position.
    Validate the relationship before saving and use database constraints to protect concurrent writes.
    Consider how a missing parent should be handled before changing records. Compare application
    validations with database constraints and explain which layer protects each invariant.

    | Record | Relationship |
    | --- | --- |
    | Course | Has many lessons |
    | Lesson | Belongs to a course |

    ```exercise
    {"prompt":"Which record owns the course identifier?","answer":"The lesson owns the course identifier because it belongs to a course."}
    ```
  MARKDOWN

  attr_reader :calls
  attr_accessor :fail_after, :before_finish, :lesson_count, :illustrate_position

  def initialize
    @calls = []
    @lesson_count = 3
  end

  def generate(generation, token:, cancelled:)
    @calls << [ generation.stage, generation.current_position ]
    server = CourseMcp::GenerationServer.new(generation_id: generation.id, token: token).build
    if generation.stage == "planning" && generation.reload.plan.empty?
      self.class.call(server, "plan_course", request_key: SecureRandom.uuid, title: "Active Record essentials",
        description: "Practical associations and validations.", category: "Programming",
        lesson_titles: (1..lesson_count).map { |number| "Lesson #{number}" })
    end
    if generation.stage == "writing"
      position = generation.current_position
      visual = position == illustrate_position ? { illustration_prompt: "Show a parent object connected to three child objects.", illustration_alt: "A parent and three children" } : {}
      self.class.call(server, "save_generated_lesson", request_key: SecureRandom.uuid, position: position, body: BODY, **visual)
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

module GenerationTestHelpers
  include ActiveJob::TestHelper

  def perform_course_steps
    perform_enqueued_jobs(only: CourseGenerationJob) { perform_enqueued_jobs(only: CourseGenerationJob) }
  end

  def approve_and_finish(generation)
    generation.reload.approve_plan!(generation.attempt, generation.course.reload.revision)
    CourseGenerationJob.enqueue(generation)
    perform_course_steps
  end
end
