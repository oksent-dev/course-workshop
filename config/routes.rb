Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  scope "/:locale", locale: /pl|en/ do
    root "pages#home", as: :localized_root
    resources :courses, only: :show, param: :slug do
      resources :lessons, only: :show
    end
  end

  root to: redirect { "/#{I18n.default_locale}" }
end
