require "digest"

class DemoCatalog
  ROOT = Rails.root.join("db/demo")

  def self.prepare!
    new.prepare!
  end

  def prepare!
    Course.transaction do
      %w[pl en].each { |language| import_course(language) }
    end
  end

  private

  def import_course(language)
    data = YAML.safe_load_file(ROOT.join("#{language}.yml"))
    attributes = data.fetch("course")
    raise ArgumentError, "Unexpected demo slug" unless DemoMode::COURSE_SLUGS.include?(attributes.fetch("slug"))

    Category.insert_all([ { name: data.fetch("category") } ], unique_by: :name)
    category = Category.lock.find_by!(name: data.fetch("category"))
    course = Course.find_or_initialize_by(slug: attributes.fetch("slug"))
    raise ArgumentError, "A generated course occupies a reserved demo slug" if course.persisted? && course.course_generation

    course.assign_attributes(attributes.merge(category: category, status: "published"))
    cover = blob("cw-demo-cover-v1.png")
    course.cover.attach(cover) unless course.cover.blob == cover
    course.save!
    data.fetch("lessons").each.with_index(1) do |entry, position|
      lesson = course.lessons.find_or_initialize_by(position: position)
      lesson.update!(title: entry.fetch("title"), body: ROOT.join(language, "#{position}.md").read)
      entry.fetch("images", []).each do |image|
        record = lesson.lesson_images.find_or_initialize_by(key: image.fetch("key"))
        record.alt_text = image.fetch("alt_text")
        file = blob(image.fetch("file"))
        record.file.attach(file) unless record.file.blob == file
        record.save!
      end
    end
    course
  end

  def blob(filename)
    service = ActiveStorage::Blob.services.fetch("bundled")
    path = service.path_for(filename)
    attributes = ImageUpload.new(path).attributes
    checksum = Digest::MD5.file(path).base64digest
    record = ActiveStorage::Blob.find_or_initialize_by(key: filename)
    if record.persisted?
      unless record.service_name == "bundled" && record.checksum == checksum
        raise ArgumentError, "Bundled assets are immutable; use a new versioned filename"
      end
    else
      record.update!(filename: filename, service_name: "bundled", byte_size: File.size(path),
        checksum: checksum, content_type: attributes.fetch(:content_type),
        metadata: attributes.fetch(:metadata).merge("identified" => true))
    end
    record
  end
end
