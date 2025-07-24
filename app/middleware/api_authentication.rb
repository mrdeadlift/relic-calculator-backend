class ApiAuthentication
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    
    # Skip authentication for non-API routes
    return @app.call(env) unless api_route?(request.path)
    
    # Skip authentication for public endpoints
    return @app.call(env) if public_endpoint?(request.path)
    
    # Check IP whitelist for admin endpoints
    if admin_endpoint?(request.path)
      return forbidden_response unless admin_ip_allowed?(request.ip)
    end
    
    # Check API key if required
    if api_key_required?
      api_key = extract_api_key(request)
      return unauthorized_response unless valid_api_key?(api_key)
    end
    
    # Log API access
    log_api_access(request) if Rails.env.production?
    
    @app.call(env)
  end

  private

  def api_route?(path)
    path.start_with?('/api/')
  end

  def public_endpoint?(path)
    public_patterns = [
      %r{^/api/v1/relics$},
      %r{^/api/v1/relics/\w+$},
      %r{^/api/v1/relics/categories$},
      %r{^/api/v1/relics/rarities$},
      %r{^/api/v1/relics/calculate$},
      %r{^/api/v1/relics/validate$},
      %r{^/api/v1/builds/shared/\w+$},
      %r{^/api/v1/documentation},
      %r{^/up$}
    ]
    
    public_patterns.any? { |pattern| path.match?(pattern) }
  end

  def admin_endpoint?(path)
    admin_patterns = [
      %r{^/api/v1/optimization/cache$},
      %r{^/api/v1/optimization/cache_stats$}
    ]
    
    admin_patterns.any? { |pattern| path.match?(pattern) }
  end

  def admin_ip_allowed?(ip)
    allowed_ips = ENV.fetch('ADMIN_IPS', '127.0.0.1,::1').split(',')
    
    # Convert to IPAddr objects for proper IP matching
    allowed_ranges = allowed_ips.map do |ip_or_range|
      begin
        IPAddr.new(ip_or_range.strip)
      rescue IPAddr::Error
        nil
      end
    end.compact
    
    client_ip = IPAddr.new(ip)
    allowed_ranges.any? { |range| range.include?(client_ip) }
  rescue IPAddr::Error
    false
  end

  def api_key_required?
    Rails.application.config.api_key_required
  end

  def extract_api_key(request)
    # Check Authorization header first
    auth_header = request.get_header('HTTP_AUTHORIZATION')
    if auth_header&.start_with?('Bearer ')
      return auth_header.sub('Bearer ', '')
    end
    
    # Check X-API-Key header
    request.get_header('HTTP_X_API_KEY') ||
    request.params['api_key']
  end

  def valid_api_key?(api_key)
    return false if api_key.blank?
    
    # In production, validate against database or secure store
    valid_keys = ENV.fetch('VALID_API_KEYS', '').split(',')
    
    if Rails.env.development?
      # Allow development key
      return true if api_key == 'dev-api-key-12345'
    end
    
    valid_keys.include?(api_key)
  end

  def log_api_access(request)
    Rails.logger.info "API Access: #{request.ip} - #{request.request_method} #{request.path} - #{Time.current}"
  end

  def unauthorized_response
    [
      401,
      {
        'Content-Type' => 'application/json',
        'WWW-Authenticate' => 'Bearer realm="API"'
      },
      [
        {
          success: false,
          message: 'Authentication required',
          error_code: 'UNAUTHORIZED',
          details: {
            authentication_methods: ['Bearer token', 'X-API-Key header', 'api_key parameter']
          },
          meta: {
            timestamp: Time.current.iso8601
          }
        }.to_json
      ]
    ]
  end

  def forbidden_response
    [
      403,
      { 'Content-Type' => 'application/json' },
      [
        {
          success: false,
          message: 'Access forbidden from this IP address',
          error_code: 'FORBIDDEN',
          meta: {
            timestamp: Time.current.iso8601
          }
        }.to_json
      ]
    ]
  end
end