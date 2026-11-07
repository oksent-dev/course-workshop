module LessonImages
  class Import
    InvalidImage = ImageUpload::InvalidImage

    def self.call(lesson:, key:, path:, alt_text:)
      new.call(lesson: lesson, key: key, path: path, alt_text: alt_text)
    end

    def call(lesson:, key:, path:, alt_text:)
      upload = ImageUpload.new(path)

      lesson.course.with_lock do
        Drafts::Access.ensure_available!(lesson.course) if lesson.course.draft?
        lesson.with_lock do
          image = lesson.lesson_images.find_or_initialize_by(key: key)
          changed = image.new_record? || image.alt_text != alt_text || !upload.stored_as?(image.file)
          image.alt_text = alt_text
          image.file = upload.attributes unless upload.stored_as?(image.file)
          image.save!
          lesson.course.increment(:revision).save! if changed
          image
        end
      end
    end
  end
end
