require "vips"
require "digest"
require "stringio"

module LessonImages
  class Import
    class InvalidImage < StandardError; end

    def self.call(lesson:, key:, path:, alt_text:)
      new.call(lesson: lesson, key: key, path: path, alt_text: alt_text)
    end

    def call(lesson:, key:, path:, alt_text:)
      bytes = File.binread(path, LessonImage::MAX_BYTES + 1)
      raise InvalidImage, "Images must be at most 5 MB." if bytes.bytesize > LessonImage::MAX_BYTES

      content_type = Marcel::MimeType.for(StringIO.new(bytes))
      unless LessonImage::CONTENT_TYPES.include?(content_type)
        raise InvalidImage, "Only PNG, JPEG, and WebP images are supported."
      end
      dimensions = validate_pixels(bytes)

      lesson.with_lock do
        image = lesson.lesson_images.find_or_initialize_by(key: key)
        image.alt_text = alt_text
        checksum = Digest::MD5.base64digest(bytes)
        unless image.file.attached? && image.file.blob.checksum == checksum && image.file.blob.service.exist?(image.file.blob.key)
          image.file = {
            io: StringIO.new(bytes), filename: File.basename(path), content_type: content_type,
            identify: false, metadata: dimensions.merge("analyzed" => true)
          }
        end
        image.save!
        image
      end
    rescue Vips::Error
      raise InvalidImage, "The image could not be decoded."
    end

    private

    def validate_pixels(bytes)
      image = Vips::Image.new_from_buffer(bytes, "", access: :sequential, fail_on: :error).autorot
      if image.width * image.height > LessonImage::MAX_PIXELS
        raise InvalidImage, "Images must contain at most 20 million pixels."
      end
      image.avg
      { "width" => image.width, "height" => image.height }
    end
  end
end
