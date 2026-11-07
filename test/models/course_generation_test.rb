require "test_helper"

class CourseGenerationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "concurrent delivery creates one course and one generation" do
    key = SecureRandom.uuid
    ready, start = Queue.new, Queue.new
    workers = 3.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          CourseGeneration.submit!(topic: "Concurrent submission", language: "en", request_key: key).id
        end
      end
    end
    3.times { ready.pop }
    3.times { start << true }
    assert_equal 1, workers.map(&:value).uniq.size
    assert_equal 1, CourseGeneration.where(request_key: key).count
    generation = CourseGeneration.find_by!(request_key: key)
    assert_equal 1, Course.where(id: generation.course_id).count
  ensure
    workers&.each(&:join)
    CourseGeneration.find_by(request_key: key)&.course&.destroy!
  end
end
