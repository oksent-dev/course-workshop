module CourseCovers
  class Import
    def self.call(course:, path:)
      upload = ImageUpload.new(path)
      course.with_lock do
        course.cover = upload.attributes unless upload.stored_as?(course.cover)
        course.save!
      end
      course.cover
    end
  end
end
