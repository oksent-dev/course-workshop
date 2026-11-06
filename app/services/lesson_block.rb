class LessonBlock
  KINDS = %w[math mermaid exercise].freeze
  LIMITS = { "math" => 2_000, "mermaid" => 6_000, "exercise" => 10_000 }.freeze
  ID = /[A-Za-z][A-Za-z0-9_]{0,39}/
  LABEL = /[\p{L}\p{N} .,;:!?%+=()\/-]{1,180}/
  NODE = /\A(#{ID})(?:\["(#{LABEL})"\]|\{"(#{LABEL})"\})\z/
  EDGE = /\A(#{ID})\s+-->(?:\|([\p{L}\p{N} .,;:!?%+=()\/-]{1,80})\|)?\s+(#{ID})\z/

  attr_reader :kind, :source, :description, :data

  def initialize(kind, source)
    @kind, @source = kind, source.strip
  end

  def valid?
    return false unless KINDS.include?(kind) && source.present? && source.length <= LIMITS.fetch(kind)

    case kind
    when "math"
      !source.match?(/\\(?:href|url|includegraphics|html[a-z]*)\b/i)
    when "mermaid"
      valid_diagram?
    when "exercise"
      @data = JSON.parse(source)
      data.is_a?(Hash) && data.keys.sort == %w[answer prompt] &&
        data.values.all? { |value| value.is_a?(String) && value.strip.present? && value.length <= 4_000 }
    end
  rescue JSON::ParserError
    false
  end

  private

  def valid_diagram?
    lines = source.lines.map(&:strip).reject(&:empty?)
    return false unless %w[flowchart\ TD flowchart\ LR].include?(lines.shift)

    nodes, edges = [], []
    descriptions = []
    lines.each do |line|
      if (node = NODE.match(line))
        nodes << node[1]
      elsif (edge = EDGE.match(line))
        edges << [ edge[1], edge[3] ]
      elsif line.start_with?("accDescr: ")
        descriptions << line.delete_prefix("accDescr: ").strip
      else
        return false
      end
    end

    @description = descriptions.first
    nodes.size.between?(1, 24) && nodes.uniq == nodes && edges.size <= 32 &&
      edges.flatten.all? { |id| nodes.include?(id) } && descriptions.size == 1 &&
      description.present? && description.match?(/\A[\p{L}\p{N} .,;:!?%+=()\/-]{1,600}\z/)
  end
end
