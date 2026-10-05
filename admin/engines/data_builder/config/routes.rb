DataBuilder::Engine.routes.draw do
  root "wizard#show"

  get "sources", to: "csvs#sources"
  post "csvs", to: "csvs#create"
  get "csvs/:id", to: "csvs#show", constraints: { id: /[a-f0-9]{16}/ }
  post "csvs/from_source/:data_source_id", to: "csvs#from_source"

  resources :builds, only: %i[ create show ] do
    member { get :download }
  end

  get "templates", to: "templates#index"
  get "templates/:name", to: "templates#show", as: :template
  put "templates/:name", to: "templates#update"
  delete "templates/:name", to: "templates#destroy"
end
