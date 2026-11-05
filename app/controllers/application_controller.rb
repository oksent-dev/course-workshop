class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  around_action :switch_locale

  private

  def switch_locale(&action)
    locale = params[:locale].presence || I18n.default_locale
    raise ActionController::RoutingError, "Not Found" unless I18n.available_locales.map(&:to_s).include?(locale.to_s)

    I18n.with_locale(locale, &action)
  end

  def default_url_options
    { locale: I18n.locale }
  end
end
