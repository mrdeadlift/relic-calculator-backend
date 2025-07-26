class ApplicationController < ActionController::API
  include ActionController::Helpers
  include ApiValidation
  
  # Error handling
  rescue_from StandardError, with: :handle_standard_error
  rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :handle_validation_error
  rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
  
  # Custom error classes
  rescue_from CalculationService::CalculationError, with: :handle_calculation_error
  rescue_from OptimizationService::OptimizationError, with: :handle_optimization_error
  rescue_from RelicValidationService::ValidationError, with: :handle_validation_service_error
  
  before_action :set_default_format
  before_action :log_request_info
  
  protected
  
  def render_success(data, message: 'Success', status: :ok, meta: {})
    response_data = ApiResponseSerializer.success(
      data,
      message: message,
      status: status,
      meta: meta.merge(default_meta)
    )
    
    render json: response_data, status: status
  end
  
  def render_error(message, status: :bad_request, error_code: nil, details: {})
    response_data = ApiResponseSerializer.error(
      message,
      status: status,
      error_code: error_code,
      details: details
    )
    
    render json: response_data, status: status
  end
  
  def render_validation_errors(record)
    response_data = ApiResponseSerializer.validation_errors(record)
    render json: response_data, status: :unprocessable_entity
  end
  
  def render_paginated_collection(collection, page_info, message: 'Data retrieved successfully')
    response_data = ApiResponseSerializer.paginated_collection(
      collection,
      page_info,
      message: message
    )
    
    render json: response_data, status: :ok
  end
  
  private
  
  def set_default_format
    request.format = :json
  end
  
  def log_request_info
    return unless Rails.env.development?
    
    Rails.logger.info "API Request: #{request.method} #{request.path}"
    Rails.logger.info "Parameters: #{filtered_params}" if filtered_params.present?
  end
  
  def filtered_params
    params.except(:controller, :action, :format)
  end
  
  def default_meta
    {
      timestamp: Time.current.iso8601,
      request_id: request.request_id,
      version: 'v1'
    }
  end
  
  # Error handlers
  def handle_not_found(exception)
    Rails.logger.warn "Record not found: #{exception.message}"
    
    render_error(
      'Resource not found',
      status: :not_found,
      error_code: 'RESOURCE_NOT_FOUND',
      details: { message: exception.message }
    )
  end
  
  def handle_validation_error(exception)
    Rails.logger.warn "Validation error: #{exception.message}"
    
    render_validation_errors(exception.record)
  end
  
  def handle_parameter_missing(exception)
    Rails.logger.warn "Parameter missing: #{exception.message}"
    
    render_error(
      "Required parameter missing: #{exception.param}",
      status: :bad_request,
      error_code: 'PARAMETER_MISSING',
      details: { missing_parameter: exception.param }
    )
  end
  
  def handle_calculation_error(exception)
    Rails.logger.error "Calculation error: #{exception.message}"
    
    render_error(
      exception.message,
      status: determine_status_from_error_code(exception.error_code),
      error_code: exception.error_code,
      details: exception.details
    )
  end
  
  def handle_optimization_error(exception)
    Rails.logger.error "Optimization error: #{exception.message}"
    
    render_error(
      exception.message,
      status: determine_status_from_error_code(exception.error_code),
      error_code: exception.error_code,
      details: exception.details
    )
  end
  
  def handle_validation_service_error(exception)
    Rails.logger.warn "Validation service error: #{exception.message}"
    
    render_error(
      exception.message,
      status: determine_status_from_error_code(exception.error_code),
      error_code: exception.error_code,
      details: exception.details
    )
  end
  
  def handle_standard_error(exception)
    Rails.logger.error "Unexpected error: #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")
    
    if Rails.env.development?
      render_error(
        "Internal server error: #{exception.message}",
        status: :internal_server_error,
        error_code: 'INTERNAL_SERVER_ERROR',
        details: {
          exception_class: exception.class.name,
          backtrace: exception.backtrace.first(10)
        }
      )
    else
      render_error(
        'An unexpected error occurred',
        status: :internal_server_error,
        error_code: 'INTERNAL_SERVER_ERROR'
      )
    end
  end
  
  def determine_status_from_error_code(error_code)
    case error_code
    when 'RELIC_NOT_FOUND', 'RESOURCE_NOT_FOUND'
      :not_found
    when 'VALIDATION_ERROR', 'INVALID_RELIC_STRUCTURE', 'INVALID_CALCULATION_CONTEXT'
      :unprocessable_entity
    when 'CONFLICTING_RELICS', 'DUPLICATE_RELICS'
      :conflict
    when 'RELIC_LIMIT_EXCEEDED', 'SELECTION_LIMIT_EXCEEDED'
      :bad_request
    when 'CALCULATION_TIMEOUT', 'OPTIMIZATION_TIMEOUT'
      :request_timeout
    else
      :bad_request
    end
  end
end
