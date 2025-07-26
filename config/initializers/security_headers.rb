# Security Headers Configuration
Rails.application.configure do
  # Content Security Policy
  config.content_security_policy do |policy|
    policy.default_src :none
    policy.script_src  :self
    policy.style_src   :self
    policy.img_src     :self, :data, :https
    policy.font_src    :self
    policy.connect_src :self
    policy.object_src  :none
    policy.frame_ancestors :none
    policy.base_uri    :self
    policy.form_action :self
  end

  # Generate nonce for inline scripts and styles
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }

  # Report CSP violations (in production)
  if Rails.env.production?
    config.content_security_policy_report_only = false
  end
end

# Custom security headers middleware
class SecurityHeadersMiddleware
  SECURITY_HEADERS = {
    # Prevent MIME type sniffing
    "X-Content-Type-Options" => "nosniff",

    # Enable XSS filtering
    "X-XSS-Protection" => "1; mode=block",

    # Prevent framing (clickjacking protection)
    "X-Frame-Options" => "DENY",

    # Strict transport security (HTTPS only)
    "Strict-Transport-Security" => "max-age=31536000; includeSubDomains",

    # Referrer policy
    "Referrer-Policy" => "strict-origin-when-cross-origin",

    # Feature policy
    "Permissions-Policy" => "geolocation=(), microphone=(), camera=()",

    # Server information hiding
    "Server" => "Nightreign API Server"
  }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)

    # Add security headers
    SECURITY_HEADERS.each do |header, value|
      headers[header] = value
    end

    # Remove server version information
    headers.delete("X-Powered-By")

    # Add API-specific headers
    if env["PATH_INFO"].start_with?("/api")
      headers["X-API-Version"] = "v1"
      headers["X-Rate-Limit-Remaining"] = calculate_rate_limit_remaining(env)
    end

    [ status, headers, response ]
  end

  private

  def calculate_rate_limit_remaining(env)
    # This would integrate with Rack::Attack or similar
    # For now, return a placeholder
    "100"
  end
end

# Add the middleware
Rails.application.config.middleware.use SecurityHeadersMiddleware
