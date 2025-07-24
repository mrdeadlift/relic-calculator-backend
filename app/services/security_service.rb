class SecurityService
  class << self
    # Encrypt sensitive data
    def encrypt_data(data, key = default_encryption_key)
      return nil if data.blank?
      
      cipher = OpenSSL::Cipher.new('AES-256-GCM')
      cipher.encrypt
      cipher.key = key
      
      iv = cipher.random_iv
      encrypted = cipher.update(data.to_s) + cipher.final
      auth_tag = cipher.auth_tag
      
      # Combine IV, auth tag, and encrypted data
      [iv, auth_tag, encrypted].map { |part| Base64.strict_encode64(part) }.join('.')
    end
    
    # Decrypt sensitive data
    def decrypt_data(encrypted_data, key = default_encryption_key)
      return nil if encrypted_data.blank?
      
      parts = encrypted_data.split('.')
      return nil unless parts.length == 3
      
      iv, auth_tag, encrypted = parts.map { |part| Base64.strict_decode64(part) }
      
      cipher = OpenSSL::Cipher.new('AES-256-GCM')
      cipher.decrypt
      cipher.key = key
      cipher.iv = iv
      cipher.auth_tag = auth_tag
      
      cipher.update(encrypted) + cipher.final
    rescue OpenSSL::Cipher::CipherError, ArgumentError
      nil
    end
    
    # Generate secure random tokens
    def generate_token(length = 32)
      SecureRandom.urlsafe_base64(length)
    end
    
    # Generate API keys
    def generate_api_key
      "nrc_#{SecureRandom.urlsafe_base64(32)}"
    end
    
    # Hash sensitive data (one-way)
    def hash_data(data, salt = nil)
      return nil if data.blank?
      
      salt ||= Rails.application.secret_key_base
      Digest::SHA256.hexdigest("#{data}#{salt}")
    end
    
    # Verify hashed data
    def verify_hash(data, hash, salt = nil)
      return false if data.blank? || hash.blank?
      
      hash_data(data, salt) == hash
    end
    
    # Sanitize input to prevent XSS
    def sanitize_input(input)
      return nil if input.blank?
      
      # Remove HTML tags and dangerous characters
      sanitized = input.to_s.gsub(/<[^>]*>/, '')
      sanitized = sanitized.gsub(/[<>"'&]/) do |char|
        case char
        when '<' then '&lt;'
        when '>' then '&gt;'
        when '"' then '&quot;'
        when "'" then '&#x27;'
        when '&' then '&amp;'
        else char
        end
      end
      
      # Limit length to prevent DoS
      sanitized.truncate(1000)
    end
    
    # Validate and sanitize relic IDs
    def sanitize_relic_id(relic_id)
      return nil if relic_id.blank?
      
      # Only allow alphanumeric characters, hyphens, and underscores
      sanitized = relic_id.to_s.gsub(/[^a-zA-Z0-9\-_]/, '')
      
      # Limit length
      sanitized.truncate(50)
    end
    
    # Rate limiting key generation
    def rate_limit_key(identifier, action = nil)
      key_parts = ['rate_limit', identifier]
      key_parts << action if action.present?
      
      Digest::SHA256.hexdigest(key_parts.join(':'))
    end
    
    # Log security events
    def log_security_event(event_type, details = {})
      security_log = {
        event_type: event_type,
        timestamp: Time.current.iso8601,
        details: details,
        request_id: Current.request_id,
        ip_address: Current.ip_address
      }
      
      Rails.logger.warn "SECURITY_EVENT: #{security_log.to_json}"
      
      # In production, also send to security monitoring system
      if Rails.env.production?
        SecurityEventJob.perform_async(security_log)
      end
    end
    
    # Validate request origin
    def validate_request_origin(request)
      origin = request.get_header('HTTP_ORIGIN')
      referer = request.get_header('HTTP_REFERER')
      
      return true if Rails.env.development?
      
      allowed_origins = Rails.application.config.allowed_origins
      
      # Check Origin header
      if origin.present?
        return allowed_origins == ['*'] || allowed_origins.include?(origin)
      end
      
      # Check Referer header as fallback
      if referer.present?
        referer_uri = URI.parse(referer)
        referer_origin = "#{referer_uri.scheme}://#{referer_uri.host}"
        referer_origin += ":#{referer_uri.port}" unless [80, 443].include?(referer_uri.port)
        
        return allowed_origins == ['*'] || allowed_origins.include?(referer_origin)
      end
      
      # No origin or referer header
      false
    rescue URI::InvalidURIError
      false
    end
    
    # Generate secure share keys
    def generate_share_key
      loop do
        key = SecureRandom.urlsafe_base64(12)
        # Ensure it doesn't conflict with existing keys
        break key unless Build.exists?(share_key: key)
      end
    end
    
    # Validate IP address format
    def valid_ip_address?(ip)
      return false if ip.blank?
      
      begin
        IPAddr.new(ip)
        true
      rescue IPAddr::Error
        false
      end
    end
    
    # Check if IP is in private range
    def private_ip?(ip)
      return false unless valid_ip_address?(ip)
      
      private_ranges = [
        IPAddr.new('10.0.0.0/8'),
        IPAddr.new('172.16.0.0/12'),
        IPAddr.new('192.168.0.0/16'),
        IPAddr.new('127.0.0.0/8'),
        IPAddr.new('::1/128'),
        IPAddr.new('fc00::/7')
      ]
      
      ip_addr = IPAddr.new(ip)
      private_ranges.any? { |range| range.include?(ip_addr) }
    rescue IPAddr::Error
      false
    end
    
    private
    
    def default_encryption_key
      key_material = Rails.application.secret_key_base
      Digest::SHA256.digest(key_material)[0, 32] # 32 bytes for AES-256
    end
  end
end

# Current request context
class Current < ActiveSupport::CurrentAttributes
  attribute :request_id, :ip_address, :user_agent
end

# Background job for security event processing (placeholder)
class SecurityEventJob
  def self.perform_async(event_data)
    # In a real application, this would use Sidekiq, Resque, or similar
    Rails.logger.info "Security event queued: #{event_data}"
  end
end