Rails.application.routes.draw do
  root "data_sources#index"

  resource :session
  resource :password, only: %i[ edit update ]

  resources :data_sources, only: %i[ index show edit update ] do
    member do
      post :toggle
      post :run
      post :upload
      get :standard_csv
    end
  end

  resources :projects, only: %i[ show edit update ] do
    member do
      post :build
    end
  end

  resources :project_builds, only: :show do
    member do
      get :csv
      get :diff
    end
  end

  resources :download_runs, only: :show do
    member do
      get :standard_csv
      get :diff
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
