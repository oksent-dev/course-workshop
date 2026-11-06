module Drafts
  class LessonContent
    MAX_LENGTH = 40_000

    def self.validate!(body, lesson: nil, learning_blocks: true)
      if body.blank? || body.length > MAX_LENGTH || body.include?("\0")
        raise Error.new("invalid_content", "Lesson body must contain 1–40,000 characters without null bytes.")
      end
      html = Commonmarker.to_html(body,
        options: { render: { unsafe: false, escape: true } }, plugins: { syntax_highlighter: nil })
      fragment = Nokogiri::HTML5.fragment(html)
      blocks = learning_blocks ? fragment.css("pre[lang]").select { |node| LessonBlock::KINDS.include?(node["lang"]) } : []
      if blocks.size > 32 || blocks.any? { |node| !LessonBlock.new(node["lang"], node.text).valid? }
        raise Error.new("invalid_content", "A math, mermaid, or exercise block is invalid, or there are more than 32 blocks. Read the authoring guide.")
      end
      blocks.select { |node| node["lang"] == "exercise" }.each do |node|
        JSON.parse(node.text).each_value { |text| validate!(text, lesson: lesson, learning_blocks: false) }
      end
      keys = lesson ? lesson.lesson_images.with_attached_file.select { |image| image.file.attached? }.map(&:key) : []
      fragment.css("img").each do |node|
        key = node["src"]&.delete_prefix("image:")
        unless node["src"]&.start_with?("image:") && keys.include?(key)
          raise Error.new("invalid_content", "Images must reference an existing image:key attachment on this lesson.")
        end
      end
    end
  end
end
