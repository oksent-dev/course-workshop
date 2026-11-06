require "test_helper"

class LessonMarkdownTest < ActionDispatch::IntegrationTest
  setup do
    @lesson = lessons(:pitch)
    @path = course_lesson_path(@lesson.course, @lesson, locale: :en)
  end

  test "Markdown renders semantic headings, lists, links, code, and tables" do
    @lesson.update!(body: <<~MARKDOWN)
      # Summary

      **Strong** and *emphasized* text, with `inline_code`.

      - First
      - Second

      1. Measure
      2. Compare

      > Keep the original observations.

      [Documentation](https://example.com/guide)
      [Polish path](https://example.com/średnia)

      ```ruby
      puts "<example>"
      ```

      | Day | Minutes |
      | --- | --- |
      | Monday | 8 |
    MARKDOWN
    get @path
    assert_response :success
    assert_select "h1", count: 1
    assert_select ".lesson-content h2", "Summary"
    assert_select ".lesson-content strong", "Strong"
    assert_select ".lesson-content em", "emphasized"
    assert_select ".lesson-content ul li", count: 2
    assert_select ".lesson-content ol li", count: 2
    assert_select ".lesson-content a[href='https://example.com/guide']"
    assert_select ".lesson-content a[href='https://example.com/%C5%9Brednia']"
    assert_select ".lesson-scroll[tabindex='0'] pre code", text: 'puts "<example>"'
    assert_select ".lesson-scroll[aria-label='Data table'] table td", text: "Monday"
  end

  test "raw HTML, scripts, and unsafe URL schemes cannot become active markup" do
    @lesson.update!(body: <<~MARKDOWN)
      <script>alert(1)</script>

      <img src="https://example.com/tracker" onerror="alert(1)">

      <iframe srcdoc="<script>alert(1)</script>"></iframe>

      [script](javascript:alert(1))
      [encoded](jav&#x61;script:alert(1))
      [data](data:text/html,test)
      [file](file:///private.txt)
      [relative host](//example.com)
      [allowed local](/en)
      [allowed secure](https://example.com)
      [anchor](#main-content)

      ![Remote illustration](https://example.com/tracker.png)
    MARKDOWN
    get @path
    assert_select ".lesson-content script, .lesson-content iframe, .lesson-content img", count: 0
    assert_select ".lesson-content [onerror], .lesson-content [style]", count: 0
    assert_select ".lesson-content a[href]" do |links|
      assert_equal [ "/en", "https://example.com", "#main-content" ], links.map { |link| link["href"] }
    end
    assert_select ".lesson-image-unavailable", text: "Image unavailable: Remote illustration"
  end

  test "Ruby, SQL and TypeScript fences receive syntax colors while preserving their source" do
    samples = {
      "rb" => "class Course < ApplicationRecord\n  validates :title, presence: true\nend\n",
      "sql" => "SELECT title FROM courses WHERE id = 1;\n",
      "typescript" => "const title: string = \"Course\";\n"
    }
    @lesson.update!(body: samples.map { |language, source| "```#{language}\n#{source}```" }.join("\n\n"))
    get @path
    assert_select ".lesson-scroll pre code.lesson-code", count: 3 do |nodes|
      assert_equal samples.values, nodes.map(&:text)
      nodes.each { |node| assert node.css("span").any? }
    end
    assert_select ".lesson-code .k", text: "class"
    assert_select ".lesson-code [style]", count: 0
  end

  test "HTML and ERB examples remain inert after highlighting" do
    source = "<script>window.codeExecuted = true</script>\n<img src=x onerror=alert(1)>\n<%= dangerous_method %>\n"
    @lesson.update!(body: "```erb\n#{source}```")
    get @path
    assert_select "code.lesson-code" do |nodes|
      assert_equal source, nodes.first.text
    end
    assert_select ".lesson-code span"
    assert_select ".lesson-content script, .lesson-content img, .lesson-content [onerror], .lesson-content [style]", count: 0
  end

  test "unknown, missing and oversized fence languages keep readable plain code" do
    large_source = "puts 'large'\n" * 2_000
    @lesson.update!(body: "```unknown-language\nputs 'unknown'\n```\n\n```\nputs 'plain'\n```\n\n```ruby\n#{large_source}```\n\nUse `inline_code`.")
    get @path
    assert_select "pre code", count: 3
    assert_select ".lesson-code", count: 0
    assert_select "pre code" do |nodes|
      assert_equal large_source, nodes.last.text
    end
    assert_select "p code", text: "inline_code"
  end

  test "code in exercise prompts and solutions is highlighted once while reserved blocks keep their renderer" do
    exercise = JSON.generate(prompt: "Explain:\n\n```ruby\nputs 1\n```", answer: "```ruby\nputs 2\n```")
    @lesson.update!(body: "```exercise\n#{exercise}\n```\n\n```math\nx = 1\n```\n\n```mermaid\nflowchart TD\naccDescr: A step.\nA[\"Start\"]\n```")
    get @path
    assert_select ".lesson-exercise code.lesson-code", count: 2
    assert_select ".lesson-code .lesson-code", count: 0
    assert_select "[data-controller='lesson-block']", count: 2
    assert_select "[data-lesson-block-target='source'] code.lesson-code", count: 0
  end

  test "an attached image has a local URL, an accessible description, and an escaped caption" do
    image = import_image
    @lesson.update!(body: '![](image:sample "A <caption>")')
    get @path
    assert_select ".lesson-content figure img[alt='A sample chart']" do |nodes|
      assert nodes.first["src"].start_with?("/rails/active_storage/blobs/")
    end
    assert_select "figcaption", "A <caption>"
    assert_select "figcaption caption", count: 0

    @lesson.update!(body: "![A different description](image:sample)")
    get @path
    assert_select ".lesson-content img[alt='A different description']"
    assert image.reload.file.attached?
  end

  test "images are scoped to their lesson and missing files retain their description" do
    image = import_image
    other = lessons(:rhythm)
    other.update!(body: "![Missing chart](image:sample)")
    get course_lesson_path(other.course, other, locale: :en)
    assert_select ".lesson-content img", count: 0
    assert_select ".lesson-image-unavailable", "Image unavailable: Missing chart"

    @lesson.update!(body: "![](image:sample)")
    image.file.blob.service.delete(image.file.blob.key)
    get @path
    assert_select ".lesson-content img", count: 0
    assert_select ".lesson-image-unavailable", "Image unavailable: A sample chart"
  end

  test "image fallback follows the interface locale while lesson text retains its language" do
    @lesson.update!(body: "![Example chart](image:missing)")
    get course_lesson_path(@lesson.course, @lesson, locale: :pl)
    assert_select ".lesson-image-unavailable", "Obraz niedostępny: Example chart"
    assert_select ".lesson-content[lang='en']"
  end

  private

  def import_image
    LessonImages::Import.call(lesson: @lesson, key: "sample", alt_text: "A sample chart",
      path: Rails.root.join("db/seeds/images/commute-times.png"))
  end
end
