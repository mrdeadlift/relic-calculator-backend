# Rate limiting configuration
class Rack::Attack
  # Enable throttling
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  
  # Global rate limiting
  throttle('requests by ip', limit: 300, period: 5.minutes) do |request|
    request.ip unless request.path.start_with?('/api/v1/relics/calculate') # More lenient for calculation endpoints
  end
  
  # Calculation endpoint specific rate limiting
  throttle('calculation requests by ip', limit: 100, period: 1.minute) do |request|
    request.ip if request.path.match?(/\/api\/v1\/relics\/(calculate|validate|compare)/) && request.post?
  end
  
  # Optimization endpoint rate limiting
  throttle('optimization requests by ip', limit: 50, period: 1.minute) do |request|
    request.ip if request.path.start_with?('/api/v1/optimization') && request.post?
  end
  
  # Build creation rate limiting
  throttle('build creation by ip', limit: 20, period: 1.hour) do |request|
    request.ip if request.path == '/api/v1/builds' && request.post?
  end
  
  # Block suspicious requests
  blocklist('block bad actors') do |request|
    # Block requests with suspicious user agents
    suspicious_agents = [
      'sqlmap', 'nikto', 'scanner', 'bot', 'crawler'
    ]
    
    user_agent = request.get_header('HTTP_USER_AGENT').to_s.downcase
    suspicious_agents.any? { |agent| user_agent.include?(agent) }
  end
  
  # Block requests with malicious payloads
  blocklist('block malicious requests') do |request|
    # Check for SQL injection patterns
    params_string = request.params.to_s.downcase
    sql_injection_patterns = [
      'union select', 'drop table', 'insert into', 'delete from',
      'update set', 'exec xp_', 'sp_executesql', '1=1', "' or '1'='1"
    ]
    
    sql_injection_patterns.any? { |pattern| params_string.include?(pattern) }
  end
  
  # Custom response for throttled requests
  self.throttled_response = ->(env) {
    retry_after = (env['rack.attack.match_data'] || {})[:period]
    
    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s,
        'X-RateLimit-Limit' => env['rack.attack.match_data'][:limit].to_s,
        'X-RateLimit-Remaining' => '0',
        'X-RateLimit-Reset' => (Time.now + retry_after).to_i.to_s
      },
      [{
        success: false,
        message: 'Rate limit exceeded. Please slow down your requests.',
        error_code: 'RATE_LIMIT_EXCEEDED',
        details: {
          retry_after: retry_after,
          limit: env['rack.attack.match_data'][:limit]
        },
        meta: {
          timestamp: Time.current.iso8601
        }
      }.to_json]
    ]
  }
  
  # Custom response for blocked requests
  self.blocklisted_response = ->(env) {
    [
      403,
      { 'Content-Type' => 'application/json' },
      [{
        success: false,
        message: 'Request blocked due to suspicious activity.',
        error_code: 'REQUEST_BLOCKED',
        meta: {
          timestamp: Time.current.iso8601
        }
      }.to_json]
    ]
  }
end

# Log blocked and throttled requests
ActiveSupport::Notifications.subscribe('rack.attack') do |name, start, finish, request_id, payload|
  request = payload[:request]
  
  case payload[:action]
  when :throttle
    Rails.logger.warn "Rate limited request: #{request.ip} - #{request.path} - #{payload[:discriminator]}"
  when :blocklist
    Rails.logger.error "Blocked request: #{request.ip} - #{request.path} - #{payload[:discriminator]}"
  end
end