# API Configuration
Rails.application.configure do
  # JSON parameter handling
  config.wrap_parameters format: [:json]
  
  # API versioning
  config.api_version = 'v1'
  config.api_base_url = ENV.fetch('API_BASE_URL', 'http://localhost:3000')
  
  # Request/Response configuration
  config.default_per_page = 20
  config.max_per_page = 100
  config.max_batch_size = 50
  
  # Calculation configuration
  config.calculation_timeout = 5.seconds
  config.optimization_timeout = 10.seconds
  config.max_relics_per_build = 9
  config.cache_expiry = 1.hour
  
  # Response format configuration
  config.include_request_id = true
  config.include_timing_info = Rails.env.development?
  config.detailed_errors = Rails.env.development?
  
  # Security configuration
  config.allowed_origins = ENV.fetch('ALLOWED_ORIGINS', '*').split(',')
  config.api_key_required = ENV.fetch('API_KEY_REQUIRED', 'false') == 'true'
  config.admin_key = ENV.fetch('ADMIN_KEY', Rails.application.secret_key_base)
end

# Custom JSON encoder for API responses
class ApiJsonEncoder
  def self.encode(object)
    case object
    when ActiveRecord::Base
      object.as_json
    when ActiveRecord::Relation
      object.map(&:as_json)
    when Hash
      object.deep_stringify_keys
    when Array
      object.map { |item| encode(item) }
    else
      object
    end
  end
end

# Monkey patch for consistent timestamp formatting
class Time
  def as_json(options = nil)
    iso8601
  end
end

class DateTime
  def as_json(options = nil)
    iso8601
  end
end

# Custom parameter handling
ActionController::Parameters.class_eval do
  def to_calculation_context
    context = {}
    
    # Standard context fields
    context['combatStyle'] = self[:combat_style] || self[:combatStyle] || 'melee'
    context['weaponType'] = self[:weapon_type] || self[:weaponType] if self[:weapon_type] || self[:weaponType]
    context['characterLevel'] = (self[:character_level] || self[:characterLevel] || 1).to_i
    
    # Parse conditions
    if self[:conditions].present?
      context['conditions'] = parse_json_param(self[:conditions])
    end
    
    # Parse base stats
    if self[:base_stats].present? || self[:baseStats].present?
      context['baseStats'] = parse_json_param(self[:base_stats] || self[:baseStats])
    end
    
    context.compact
  end
  
  private
  
  def parse_json_param(param)
    case param
    when String
      begin
        JSON.parse(param)
      rescue JSON::ParserError
        {}
      end
    when Hash
      param.to_h
    else
      {}
    end
  end
end

# Request logging middleware
class ApiRequestLogger
  def initialize(app)
    @app = app
  end
  
  def call(env)
    start_time = Time.current
    request = Rack::Request.new(env)
    
    # Log incoming request
    if Rails.env.development? && request.path.start_with?('/api')
      Rails.logger.info "API Request: #{request.request_method} #{request.path}"
      Rails.logger.info "Parameters: #{request.params}" if request.params.any?
    end
    
    status, headers, response = @app.call(env)
    
    # Add timing headers
    duration = ((Time.current - start_time) * 1000).round(2)
    headers['X-Runtime'] = "#{duration}ms"
    headers['X-Request-Id'] = env['HTTP_X_REQUEST_ID'] || SecureRandom.uuid
    
    # Log response
    if Rails.env.development? && request.path.start_with?('/api')
      Rails.logger.info "API Response: #{status} (#{duration}ms)"
    end
    
    [status, headers, response]
  end
end

# Add the middleware
Rails.application.config.middleware.use ApiRequestLogger