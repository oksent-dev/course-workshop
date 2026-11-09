require "test_helper"
require "open3"
require "rbconfig"

class DemoCatalogTest < ActiveSupport::TestCase
  test "repeated preparation preserves links progress and unrelated courses without duplicating assets" do
    original = courses(:listening).attributes
    DemoCatalog.prepare!
    courses = Course.where(slug: DemoMode::COURSE_SLUGS).order(:slug)
    assert_equal %w[en pl], courses.pluck(:language).sort
    lessons = courses.flat_map { |course| course.lessons.to_a }
    assert_equal 8, lessons.size
    profile = LearnerProfile.create!(key: SecureRandom.hex(32))
    profile.progress_for(lessons.first).complete!
    ids = lessons.map(&:id)
    counts = [ Course, Lesson, LessonImage, ActiveStorage::Blob, ActiveStorage::Attachment ].map(&:count)
    DemoCatalog.prepare!
    assert_equal counts, [ Course, Lesson, LessonImage, ActiveStorage::Blob, ActiveStorage::Attachment ].map(&:count)
    assert_equal ids, courses.flat_map { |course| course.lessons.reload.map(&:id) }
    assert profile.progress_for(lessons.first).completed_at
    assert_equal original, Course.find(original.fetch("id")).attributes
    assert courses.all? { |course| course.cover.blob.service_name == "bundled" }
    assert_nil courses.first.generated_at
  end

  test "bundled assets reject writes and traversal while attachment purges preserve source files" do
    DemoCatalog.prepare!
    cover = Course.find_by!(slug: DemoMode::COURSE_SLUGS.first).cover
    service = cover.blob.service
    key = cover.blob.key
    assert_equal "/demo-media/#{key}", cover.blob.url
    assert_raises(ActiveStorage::InvalidKeyError) { service.download("../secret.jpg") }
    assert_raises(NotImplementedError) { service.upload(key, StringIO.new("changed")) }
    assert_raises(NotImplementedError) { service.compose([], key) }
    assert_raises(NotImplementedError) { service.url_for_direct_upload(key) }
    cover.purge
    assert service.exist?(key)
  end

  test "trusted course code examples produce the documented results in both languages" do
    %w[pl en].each do |language|
      { 2 => "Mean: 12.0 min\nMedian: 8 min\n", 4 => "8\n7.0\n" }.each do |lesson, expected|
        body = DemoCatalog::ROOT.join(language, "#{lesson}.md").read
        code = body.match(/```ruby\n(.*?)```/m)[1]
        output, status = Open3.capture2(RbConfig.ruby, "-e", code)
        assert status.success?
        assert_equal expected, output
      end
    end
  end
end
