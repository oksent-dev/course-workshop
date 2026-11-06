require "test_helper"

class LessonBlocksTest < ActionDispatch::IntegrationTest
  setup do
    @lesson = lessons(:pitch)
  end

  test "recognized fences become explicit components and ordinary code stays code" do
    @lesson.update!(body: <<~MARKDOWN)
      ## A calculation

      \`\`\`math
      x = 2 + 2
      \`\`\`

      \`\`\`mermaid
      flowchart TD
        accDescr: Measure then compare.
        A["Measure"]
        B["Compare"]
        A --> B
      \`\`\`

      \`\`\`exercise
      {"prompt":"Compute **2 + 2**.","answer":"The answer is **4**."}
      \`\`\`

      \`\`\`ruby
      puts "hello"
      \`\`\`
    MARKDOWN
    visit_lesson
    assert_response :success
    assert_select "[data-controller='lesson-block']", count: 2
    assert_select ".lesson-block [data-lesson-block-target=source]", count: 2
    assert_select ".lesson-exercise strong", "2 + 2"
    assert_select ".lesson-exercise-answer:not([open])"
    assert_select ".lesson-exercise-solution strong", "4"
    assert_select ".lesson-scroll pre code", text: 'puts "hello"'
    assert_select ".lesson-scroll .lesson-scroll", count: 0
    assert_select "link[href*='lesson_math']"
  end

  test "malformed and unsafe blocks fail independently without executing generated HTML" do
    @lesson.update!(body: <<~MARKDOWN)
      Before the errors.

      \`\`\`exercise
      {"prompt": "Missing an answer"}
      \`\`\`

      \`\`\`mermaid
      %%{init: {"securityLevel":"loose"}}%%
      flowchart TD
        A["<img src=x onerror=alert(1)>"]
      \`\`\`

      \`\`\`math
      \\href{javascript:alert(1)}{click}
      \`\`\`

      After the errors.
    MARKDOWN
    visit_lesson
    assert_select ".lesson-block-error", count: 3
    assert_select ".lesson-content p", "After the errors."
    assert_select ".lesson-content script, .lesson-content img, .lesson-content iframe", count: 0
    assert_select "[data-controller='lesson-block']", count: 0
  end

  test "exercise Markdown uses the same escaping and does not recursively render blocks" do
    data = { prompt: "<script>alert(1)</script>", answer: "\`\`\`math\nx=4\n\`\`\`" }
    @lesson.update!(body: "\`\`\`exercise\n#{data.to_json}\n\`\`\`")
    visit_lesson
    assert_select ".lesson-exercise script", count: 0
    assert_select ".lesson-exercise-prompt", text: /<script>alert\(1\)<\/script>/
    assert_select ".lesson-exercise pre code", "x=4"
    assert_select ".lesson-exercise [data-controller='lesson-block']", count: 0
  end

  test "blocks have localized controls and a per-lesson rendering limit" do
    @lesson.update!(body: 33.times.map { "\`\`\`math\nx=1\n\`\`\`" }.join("\n\n"))
    visit_lesson
    assert_select "[data-controller='lesson-block']", count: 32
    assert_select ".lesson-block-error", count: 1

    @lesson.update!(body: "\`\`\`exercise\n#{ { prompt: "Compute", answer: "4" }.to_json }\n\`\`\`")
    get course_lesson_path(@lesson.course, @lesson, locale: :pl)
    assert_select "summary", "Porównaj swoją odpowiedź"
  end

  private

  def visit_lesson
    get course_lesson_path(@lesson.course, @lesson, locale: :en)
  end
end
