module DemoMode
  COURSE_SLUGS = %w[demo-statystyka-przy-kawie demo-statistics-over-coffee].freeze

  def self.enabled?
    Rails.configuration.x.demo_mode == true
  end
end
