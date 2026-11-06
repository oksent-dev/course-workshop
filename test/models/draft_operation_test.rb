require "test_helper"

class DraftOperationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "concurrent identical retries commit one course and replay the same result" do
    key = SecureRandom.uuid
    slug = "concurrent-#{key}"
    arguments = { slug: slug }
    threads = 3.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          DraftOperation.perform!(request_key: key, operation: "create", arguments: arguments) do
            course = Course.create!(category: categories(:music), slug: slug, title: "Concurrent draft", description: "Read.", language: "en")
            { course_id: course.id }
          end
        end
      end
    end
    results = threads.map(&:value)
    assert_equal 1, results.uniq.size
    assert_equal 1, Course.where(slug: slug).count
    assert_equal 1, DraftOperation.where(request_key: key).count
  ensure
    threads&.each(&:join)
    Course.where(slug: slug).destroy_all if slug
    DraftOperation.where(request_key: key).delete_all if key
  end
end
