require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  # API-specific production settings
  config.api_base_url = ENV.fetch("API_BASE_URL", "https://api.nightreign-calculator.com")
  config.detailed_errors = false
  config.include_timing_info = false
  config.log_api_requests = false

  # Security settings
  config.api_key_required = ENV.fetch("API_KEY_REQUIRED", "false") == "true"
  config.allowed_origins = ENV.fetch("ALLOWED_ORIGINS", "https://nightreign-calculator.com").split(",")

  # Performance settings
  config.calculation_timeout = 5.seconds
  config.optimization_timeout = 10.seconds
  config.cache_expiry = 1.hour

  # Redis cache for production (if available)
  if ENV["REDIS_URL"].present?
    config.cache_store = :redis_cache_store, {
      url: ENV["REDIS_URL"],
      expires_in: 1.hour,
      namespace: "nightreign_api",
      pool_size: 5,
      pool_timeout: 5
    }
  end

  # Enhanced security headers
  config.force_ssl = true
  config.ssl_options = {
    redirect: { exclude: ->(request) { request.path == "/up" } },
    secure_cookies: true,
    hsts: {
      expires: 1.year,
      include_subdomains: true,
      preload: true
    }
  }

  # Host authorization for API
  allowed_hosts = ENV.fetch("ALLOWED_HOSTS", config.api_base_url).split(",")
  config.hosts = allowed_hosts.map { |host| URI.parse(host).host rescue host }

  # Disable detailed error pages
  config.consider_all_requests_local = false

  # Enhanced logging for security
  config.log_tags = [ :request_id, :remote_ip ]

  # Content Security Policy for API responses
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_report_only = false

  # Database connection pool settings
  config.database_selector = { delay: 2.seconds }
  config.database_resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver
  config.database_resolver_context = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session

  # Active Record encryption (if needed for sensitive data)
  # config.active_record.encryption.key_derivation_salt = Rails.application.credentials.active_record_encryption.key_derivation_salt
  # config.active_record.encryption.primary_key = Rails.application.credentials.active_record_encryption.primary_key
  # config.active_record.encryption.deterministic_key = Rails.application.credentials.active_record_encryption.deterministic_key

  # Parameter filtering for logs
  config.filter_parameters += [
    :password, :api_key, :secret, :token, :private_key, :public_key,
    :ssn, :credit_card, :cvv, :authorization
  ]
end
