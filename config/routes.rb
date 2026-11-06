Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  scope "/:locale", locale: /pl|en/ do
    root "pages#home", as: :localized_root
    resources :drafts, only: [ :index, :show, :update ]
    resources :courses, only: :show, param: :slug do
      resources :lessons, only: :show do
        resource :completion, only: [ :create, :destroy ]
        resource :conversation, only: :show do
          resources :exchanges, only: [ :create, :destroy ], controller: :conversations
        end
      end
    end
  end

  root to: redirect { "/#{I18n.default_locale}" }
end
