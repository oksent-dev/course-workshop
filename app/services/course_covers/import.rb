module CourseCovers
  class Import
    def self.call(course:, path:)
      upload = ImageUpload.new(path)
      course.with_lock do
        Drafts::Access.ensure_available!(course) if course.draft?
        unless upload.stored_as?(course.cover)
          course.cover = upload.attributes
          course.increment(:revision).save!
        end
      end
      course.cover
    end
  end
end
