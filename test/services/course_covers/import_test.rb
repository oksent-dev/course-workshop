require "test_helper"
require "tempfile"

class CourseCoversImportTest < ActiveSupport::TestCase
  setup do
    @course = courses(:listening)
    @path = Rails.root.join("db/seeds/images/commute-times.png")
  end

  test "cover bytes persist, repeated imports reuse the blob, and cards get a WebP thumbnail" do
    cover = CourseCovers::Import.call(course: @course, path: @path)
    blob_id = cover.blob.id
    assert_equal File.binread(@path), @course.reload.cover.download
    assert_no_difference "ActiveStorage::Blob.count" do
      CourseCovers::Import.call(course: @course, path: @path)
      assert_equal blob_id, @course.reload.cover.blob.id
    end
    thumbnail = @course.cover.variant(:card).processed.download
    assert_equal "image/webp", Marcel::MimeType.for(StringIO.new(thumbnail))
    image = Vips::Image.new_from_buffer(thumbnail, "")
    assert_equal [ 960, 540 ], [ image.width, image.height ]
  end

  test "an invalid replacement leaves the saved cover intact" do
    CourseCovers::Import.call(course: @course, path: @path)
    blob_id = @course.cover.blob.id
    Tempfile.create([ "invalid-cover", ".png" ]) do |file|
      file.write("<svg><script>not an image</script></svg>")
      file.flush
      assert_no_difference "ActiveStorage::Blob.count" do
        assert_raises(ImageUpload::InvalidImage) { CourseCovers::Import.call(course: @course, path: file.path) }
      end
    end
    assert_equal blob_id, @course.reload.cover.blob.id
    assert_equal File.binread(@path), @course.cover.download
  end

  test "import restores a missing stored file" do
    cover = CourseCovers::Import.call(course: @course, path: @path)
    cover.blob.service.delete(cover.blob.key)
    CourseCovers::Import.call(course: @course, path: @path)
    assert_equal File.binread(@path), @course.reload.cover.download
  end
end
