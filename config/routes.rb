Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  namespace :api do
    namespace :v1 do
      # API Documentation
      resources :documentation, only: [:index] do
        collection do
          get 'openapi.json', action: :openapi_spec
          get :postman, action: :postman_collection
        end
      end
      
      # Relic-related routes
      resources :relics, only: [:index, :show] do
        collection do
          post :calculate
          post :validate
          post :compare
          get :categories
          get :rarities
        end
      end
      
      # Optimization routes
      resource :optimization, only: [] do
        collection do
          post :suggest
          post :analyze
          post :compare
          post :meta_builds
          get :cache_stats
          delete :cache, action: :clear_cache
          post :batch_calculate
        end
      end
      
      # Build management routes
      resources :builds do
        member do
          post :clone
          post :share
          post :calculate, action: :calculate_build
          post :optimize, action: :optimize_build
          post :add_relic
          delete 'remove_relic/:relic_id', action: :remove_relic
          post :reorder_relics
        end
        
        collection do
          get 'shared/:share_key', action: :shared
        end
      end
      
      # Admin routes
      namespace :admin do
        # Relic management
        resources :relics, only: [:create, :update, :destroy] do
          collection do
            post :validate, action: :validate_data
            post :import, action: :import_relics
            get :export, action: :export_relics
          end
        end
        
        # System statistics
        get :statistics
      end
    end
  end

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
