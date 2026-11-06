require "uri"

class LessonMarkdown
  TAGS = %w[p br h2 h3 h4 h5 h6 ul ol li strong em del blockquote pre code a hr
    table thead tbody tr th td div span figure figcaption img section details summary].freeze
  ATTRIBUTES = %w[href title class start colspan rowspan scope alt src width height loading decoding
    tabindex role aria-label hidden data-controller data-action data-lesson-image-target
    data-lesson-block-module-value data-lesson-block-error-value data-lesson-block-loading-value
    data-lesson-block-target].freeze

  def initialize(lesson, view:, source: lesson.body, blocks: true)
    @lesson = lesson
    @view = view
    @source = source
    @blocks = blocks
  end

  def render
    html = Commonmarker.to_html(@source,
      options: {
        render: { unsafe: false, escape: true, hardbreaks: false },
        extension: { header_ids: nil, tasklist: false, shortcodes: false }
      },
      plugins: { syntax_highlighter: nil })
    fragment = Nokogiri::HTML5.fragment(html)

    fragment.css("h1").each { |heading| heading.name = "h2" }
    fragment.css("a").each { |link| link.remove_attribute("href") unless allowed_link?(link["href"]) }
    render_images(fragment)
    highlight_code(fragment)
    render_blocks(fragment) if @blocks
    wrap_scrollable_blocks(fragment)
    @view.sanitize(fragment.to_html, tags: TAGS, attributes: ATTRIBUTES)
  end

  private

  def highlight_code(fragment)
    fragment.css("pre[lang]").reject { |node| LessonBlock::KINDS.include?(node["lang"]) }.first(32).each do |node|
      code = node.at_css("code")
      next unless code
      highlighted = LessonCode.highlight(code.text, language: node["lang"])
      next unless highlighted
      code.inner_html = highlighted
      code["class"] = "lesson-code"
    end
  end

  def render_blocks(fragment)
    count = 0
    fragment.css("pre[lang]").each do |node|
      kind = node["lang"]
      next unless LessonBlock::KINDS.include?(kind)
      count += 1
      block = LessonBlock.new(kind, node.text)
      markup = if count > 32 || !block.valid?
        @view.render("lessons/invalid_block", source: node.text)
      elsif kind == "exercise"
        prompt, answer = block.data.values_at("prompt", "answer").map do |source|
          self.class.new(@lesson, view: @view, source: source, blocks: false).render
        end
        @view.render("lessons/exercise", prompt: prompt, answer: answer)
      else
        @view.render("lessons/rendered_block", block: block)
      end
      node.replace(Nokogiri::HTML5.fragment(markup))
    end
  end

  def allowed_link?(url)
    return false if url.blank? || url.match?(/[\x00-\x20\\]/)
    return true if url.start_with?("#")
    return true if url.start_with?("/") && !url.start_with?("//")

    uri = URI.parse(URI::DEFAULT_PARSER.escape(url))
    %w[http https].include?(uri.scheme&.downcase) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def render_images(fragment)
    images = @lesson.lesson_images.with_attached_file.index_by(&:key)
    fragment.css("img").each do |node|
      key = node["src"]&.match(/\Aimage:([a-z0-9]+(?:-[a-z0-9]+)*)\z/)&.[](1)
      image = images[key]
      alt_text = node["alt"].presence || image&.alt_text || @view.t("reader.image_without_description")
      image = nil unless image&.file&.attached? &&
        LessonImage::CONTENT_TYPES.include?(image.file.blob.content_type) &&
        image.file.blob.service.exist?(image.file.blob.key)
      standalone = node.parent.name == "p" && node.parent.children.all? { |child| child == node || child.text? && child.text.strip.empty? }
      markup = @view.render("lessons/image", image: image, alt_text: alt_text, caption: node["title"], standalone: standalone)
      (standalone ? node.parent : node).replace(Nokogiri::HTML5.fragment(markup))
    end
  end

  def wrap_scrollable_blocks(fragment)
    fragment.css("pre, table").each do |node|
      next if node.ancestors.any? { |parent| parent["data-controller"] == "lesson-block" || parent["class"]&.split&.include?("lesson-scroll") }
      label = @view.t("reader.#{node.name == "pre" ? "code_sample" : "data_table"}")
      wrapper = Nokogiri::XML::Node.new("div", fragment.document)
      wrapper["class"] = "lesson-scroll"
      wrapper["tabindex"] = "0"
      wrapper["role"] = "region"
      wrapper["aria-label"] = label
      node.add_previous_sibling(wrapper)
      wrapper.add_child(node)
    end
  end
end
