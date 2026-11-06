namespace :courses do
  desc "Attach a local course cover: COURSE=slug FILE=path"
  task attach_cover: :environment do
    course = Course.find_by!(slug: ENV.fetch("COURSE"))
    cover = CourseCovers::Import.call(course: course, path: ENV.fetch("FILE"))
    cover.variant(:card).processed
    puts "Cover attached to #{course.slug}."
  rescue KeyError, Errno::ENOENT, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid, ImageUpload::InvalidImage => error
    abort error.message
  end
end
