namespace :lessons do
  desc "Attach a local image: LESSON=ID KEY=name FILE=path ALT=description"
  task attach_image: :environment do
    image = LessonImages::Import.call(
      lesson: Lesson.find(ENV.fetch("LESSON")),
      key: ENV.fetch("KEY"), path: ENV.fetch("FILE"), alt_text: ENV.fetch("ALT")
    )
    puts "Image attached to lesson #{image.lesson_id}."
    puts "Markdown: ![](image:#{image.key})"
  rescue KeyError, Errno::ENOENT, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid, LessonImages::Import::InvalidImage => error
    abort error.message
  end
end
