class PagesController < ApplicationController
  def home
    @categories = Category.joins(:courses).distinct.order(:name).preload(:courses).load
  end
end
