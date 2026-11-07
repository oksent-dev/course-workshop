Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  scope "/:locale", locale: /pl|en/ do
    root "pages#home", as: :localized_root
    resource :settings, only: [ :show, :update ]
    resources :drafts, only: [ :index, :show, :update ]
    resources :generations, only: [ :new, :create, :show ] do
      post :cancel, on: :member
      post :retry, on: :member, action: :retry_generation
      post :retry_cover, on: :member
      post :approve_plan, on: :member
    end
    resources :courses, only: :show, param: :slug do
      resource :conversation, only: :show do
        post "changes/:change_id/undo", to: "conversations#undo", as: :undo_change
        post "covers/:cover_id/retry", to: "conversations#retry_cover", as: :retry_cover
        delete "covers/:cover_id", to: "conversations#cancel_cover", as: :cancel_cover
        resources :exchanges, only: [ :create, :destroy ], controller: :conversations
      end
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
