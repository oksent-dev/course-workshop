require "test_helper"
require "tempfile"

class LessonImagesImportTest < ActiveSupport::TestCase
  setup do
    @lesson = lessons(:pitch)
    @path = Rails.root.join("db/seeds/images/commute-times.png")
  end

  test "import persists bytes on disk and repeating it reuses the image and blob" do
    image = import(@path)
    blob_id = image.file.blob.id
    assert_equal File.binread(@path), image.reload.file.download
    assert_equal "image/png", image.file.blob.content_type
    assert_equal [ 1200, 650 ], image.file.blob.metadata.values_at("width", "height")

    assert_no_difference [ "LessonImage.count", "ActiveStorage::Blob.count" ] do
      repeated = import(@path, alt_text: "Updated description")
      assert_equal image.id, repeated.id
      assert_equal blob_id, repeated.file.blob.id
      assert_equal "Updated description", repeated.alt_text
    end
  end

  test "a missing stored file can be restored by importing again" do
    image = import(@path)
    image.file.blob.service.delete(image.file.blob.key)
    restored = import(@path)
    assert_equal image.id, restored.id
    assert_equal File.binread(@path), restored.file.download
  end

  test "rejects SVG, spoofed extensions, broken images, and oversized inputs" do
    samples = [
      '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>',
      "<html>Not an image</html>",
      "\x89PNG\r\n\x1a\n".b + "broken",
      "x" * (LessonImage::MAX_BYTES + 1)
    ]
    samples.each do |bytes|
      with_file(bytes) do |path|
        assert_no_difference [ "LessonImage.count", "ActiveStorage::Blob.count" ] do
          assert_raises(LessonImages::Import::InvalidImage) { import(path) }
        end
      end
    end
  end

  test "requires a stable key and alternative text without replacing an existing image" do
    image = import(@path)
    blob_id = image.file.blob.id
    assert_raises(ActiveRecord::RecordInvalid) { import(@path, alt_text: "") }
    assert_equal blob_id, image.reload.file.blob.id
    assert_equal "Sample chart", image.alt_text
    assert_raises(ActiveRecord::RecordInvalid) { import(@path, key: "../invalid") }
  end

  test "accepts decoded JPEG and WebP and limits pixel dimensions" do
    source = Vips::Image.black(2, 2)
    { ".jpg" => "image/jpeg", ".webp" => "image/webp" }.each do |extension, content_type|
      with_file(source.write_to_buffer(extension)) do |path|
        assert_equal content_type, import(path).file.blob.content_type
      end
    end

    oversized = Vips::Image.black(5000, 5000).write_to_buffer(".png")
    with_file(oversized) do |path|
      assert_raises(LessonImages::Import::InvalidImage) { import(path) }
    end
  end

  private

  def import(path, key: "sample", alt_text: "Sample chart")
    LessonImages::Import.call(lesson: @lesson, key: key, path: path, alt_text: alt_text)
  end

  def with_file(bytes)
    Tempfile.create([ "lesson-image", ".png" ]) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      yield file.path
    end
  end
end
