class LessonCode
  MAX_BYTES = 20_000
  LANGUAGES = %w[ruby erb javascript typescript jsx tsx python sql html css json yaml shell
    powershell java c cpp csharp go rust docker toml markdown diff].freeze

  def self.highlight(source, language:)
    return if source.bytesize > MAX_BYTES || !language.to_s.match?(/\A[a-zA-Z0-9_+-]{1,40}\z/)
    lexer_class = Rouge::Lexer.find(language.downcase)
    return unless lexer_class && LANGUAGES.include?(lexer_class.tag)

    Rouge::Formatters::HTML.new.format(lexer_class.new.lex(source))
  rescue StandardError => error
    Rails.logger.warn("Code highlighting skipped (#{error.class.name})")
    nil
  end
end
