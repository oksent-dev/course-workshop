require "vips"
require "digest"
require "stringio"

class ImageUpload
  class InvalidImage < StandardError; end

  CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  MAX_BYTES = 5.megabytes
  MAX_PIXELS = 20_000_000

  def initialize(path = nil, bytes: nil, filename: nil)
    @filename = filename || File.basename(path)
    @bytes = bytes || File.binread(path, MAX_BYTES + 1)
    raise InvalidImage, "Images must be at most 5 MB." if @bytes.bytesize > MAX_BYTES

    @content_type = Marcel::MimeType.for(StringIO.new(@bytes))
    raise InvalidImage, "Only PNG, JPEG, and WebP images are supported." unless CONTENT_TYPES.include?(@content_type)

    image = Vips::Image.new_from_buffer(@bytes, "", access: :sequential, fail_on: :error).autorot
    raise InvalidImage, "Images must contain at most 20 million pixels." if image.width * image.height > MAX_PIXELS

    image.avg
    @metadata = { "width" => image.width, "height" => image.height, "analyzed" => true }
  rescue Vips::Error
    raise InvalidImage, "The image could not be decoded."
  end

  def stored_as?(attachment)
    attachment.attached? && attachment.blob.checksum == Digest::MD5.base64digest(@bytes) &&
      attachment.blob.service.exist?(attachment.blob.key)
  end

  def attributes
    { io: StringIO.new(@bytes), filename: @filename, content_type: @content_type, identify: false, metadata: @metadata }
  end
end
