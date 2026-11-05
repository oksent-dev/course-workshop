class CoursesController < ApplicationController
  def show
    @course = Course.find_by!(slug: params[:slug])
    @lessons = @course.lessons.outline.to_a
  end
end
