require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Store
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # API-only configuration
    config.api_only = true
    
    # CORS configuration
    config.middleware.insert_before 0, Rack::Cors do
      allow do
        origins '*' # In production, replace with specific origins
        resource '*',
          headers: :any,
          methods: [:get, :post, :put, :patch, :delete, :options, :head],
          expose: ['X-Request-Id', 'X-Runtime']
      end
    end
    
    # JSON parameter parsing
    config.middleware.use ActionDispatch::ContentSecurityPolicy::Middleware
    config.force_ssl = false # Set to true in production
    
    # Request ID tracking
    config.log_tags = [:request_id]
    
    # Rate limiting middleware (basic implementation)
    config.middleware.use Rack::Attack if defined?(Rack::Attack)
    
    # API authentication middleware
    config.middleware.use ApiAuthentication
  end
end
