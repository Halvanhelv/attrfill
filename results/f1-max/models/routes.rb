Rails.application.routes.draw do
  root "cards#new"

  resources :cards, only: %i[new create show]
  resources :batches, only: %i[index create show] do
    get :download, on: :member
  end
  resources :reviews, only: %i[index update]
  resources :review_groups, only: %i[show create] do
    post :undo, on: :collection
  end
  resource :metrics, only: :show

  namespace :api do
    resource :extraction, only: :create
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
