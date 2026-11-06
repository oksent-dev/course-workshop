demo = YAML.safe_load_file(Rails.root.join("db/seeds/everyday-statistics.yml"))
course_attributes = demo.fetch("course")
category_name = demo.fetch("category")

Category.transaction do
  Category.insert_all([ { name: category_name } ], unique_by: :name)
  category = Category.lock.find_by!(name: category_name)
  course = category.courses.find_or_initialize_by(slug: course_attributes.fetch("slug"))
  course.update!(course_attributes)

  demo.fetch("lessons").each.with_index(1) do |attributes, position|
    lesson = course.lessons.find_or_initialize_by(position: position)
    lesson.update!(attributes.except("images"))
    attributes.fetch("images", []).each do |image|
      LessonImages::Import.call(
        lesson: lesson, key: image.fetch("key"), alt_text: image.fetch("alt_text"),
        path: Rails.root.join("db/seeds/images", image.fetch("file"))
      )
    end
  end
end
