class AssistantContext
  def self.mode(course)
    course.draft? ? "editor" : "tutor"
  end

  def self.version(course)
    Digest::SHA256.hexdigest([
      course.cache_key_with_version, course.status, course.revision,
      course.lessons.count, course.lessons.maximum(:updated_at)&.iso8601(6),
      course.cover_attachment&.blob_id
    ].to_json)
  end
end
