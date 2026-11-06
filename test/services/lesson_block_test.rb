require "test_helper"

class LessonBlockTest < ActiveSupport::TestCase
  test "the supported flowchart subset accepts decisions and labeled edges" do
    block = LessonBlock.new("mermaid", <<~SOURCE)
      flowchart TD
        accDescr: Choose the middle for a typical result.
        A{"Typical result?"}
        B["Median"]
        A -->|Yes| B
    SOURCE
    assert block.valid?
    assert_equal "Choose the middle for a typical result.", block.description
  end

  test "diagrams reject configuration, links, markup, undefined nodes, and excessive size" do
    sources = [
      "%%{init: {}}%%\nflowchart TD\nA --> B",
      "flowchart TD\naccDescr: %%{init: {}}%%\nA[\"A\"]",
      "flowchart TD\naccDescr: A chart.\nA[\"<script>alert(1)</script>\"]",
      "flowchart TD\naccDescr: A chart.\nA[\"A\"]\nclick A \"https://example.com\"",
      "flowchart TD\naccDescr: A chart.\nA[\"A\"]\nA --> B",
      "flowchart TD\naccDescr: A chart.\nA[\"A\"]\nA[\"B\"]",
      "flowchart TD\naccDescr: A chart.\n" + 25.times.map { |n| "A#{n}[\"A\"]" }.join("\n"),
      "flowchart TD\nA[\"A\"]"
    ]
    sources.each { |source| assert_not LessonBlock.new("mermaid", source).valid?, source }
  end

  test "math rejects oversized input and commands that request trusted HTML or URLs" do
    assert LessonBlock.new("math", '\frac{1}{n}\sum_{i=1}^{n}x_i').valid?
    [ "", "x" * 2001, '\href{javascript:alert(1)}{click}', '\htmlStyle{color:red}{x}' ].each do |source|
      assert_not LessonBlock.new("math", source).valid?
    end
  end

  test "exercises require only two bounded nonempty Markdown strings" do
    assert LessonBlock.new("exercise", { prompt: "Compute **2 + 2**.", answer: "4" }.to_json).valid?
    [
      "broken JSON", "[]", '{"prompt": [], "answer": "4"}',
      { prompt: " ", answer: "4" }.to_json,
      { prompt: "A", answer: "B", script: "alert(1)" }.to_json,
      { prompt: "A", answer: "B" * 4001 }.to_json
    ].each { |source| assert_not LessonBlock.new("exercise", source).valid? }
  end
end
