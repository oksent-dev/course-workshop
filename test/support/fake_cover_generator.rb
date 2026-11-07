class FakeCoverGenerator
  attr_reader :calls
  attr_accessor :error, :before_finish

  def initialize
    @calls = []
  end

  def generate(course, cancelled:, run: nil, brief: nil)
    @calls << course.id
    raise LocalAi::Error, error if error
    before_finish&.call
    ImageUpload.new(Rails.root.join("db/seeds/images/commute-times.png"))
  end

  def illustrate(generation, cancelled:, run: nil)
    generate(generation.course, cancelled: cancelled, run: run)
  end
end
