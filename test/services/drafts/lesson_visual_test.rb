require "test_helper"

class LessonVisualTest < ActiveSupport::TestCase
  test "generated material accepts supported visuals and rejects text and pretend visuals" do
    [
      "| Option | Result |\n| --- | --- |\n| A | 2 |",
      "```math\nx = 2 + 3\n```",
      "```mermaid\nflowchart LR\naccDescr: A leads to B\nA[\"Observe\"]\nB[\"Compare\"]\nA --> B\n```"
    ].each { |body| Drafts::LessonContent.validate!(body, require_visual: true) }
    [ "Text only.", "<table><tr><td>Fake</td></tr></table>", "```markdown\n| A | B |\n|---|---|\n|1|2|\n```" ].each do |body|
      error = assert_raises(Drafts::Error) { Drafts::LessonContent.validate!(body, require_visual: true) }
      assert_equal "missing_visual", error.code
    end
    Drafts::LessonContent.validate!("Existing hand-authored text remains valid.")
  end
end
