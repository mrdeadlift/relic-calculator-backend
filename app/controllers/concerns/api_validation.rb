module ApiValidation
  extend ActiveSupport::Concern

  # Validation error types
  VALIDATION_ERRORS = {
    required_param_missing: "REQUIRED_PARAMETER_MISSING",
    invalid_param_format: "INVALID_PARAMETER_FORMAT",
    param_out_of_range: "PARAMETER_OUT_OF_RANGE",
    invalid_enum_value: "INVALID_ENUM_VALUE",
    array_too_large: "ARRAY_TOO_LARGE",
    string_too_long: "STRING_TOO_LONG",
    invalid_json: "INVALID_JSON_FORMAT"
  }.freeze

  # Parameter validation methods
  def validate_required_params(*param_names)
    missing_params = param_names.select { |param| params[param].blank? }

    if missing_params.any?
      render_validation_error(
        "Required parameters missing: #{missing_params.join(', ')}",
        :required_param_missing,
        { missing_parameters: missing_params }
      )
      return false
    end

    true
  end

  def validate_param_format(param_name, format_regex, error_message = nil)
    param_value = params[param_name]
    return true if param_value.blank?

    unless param_value.to_s.match?(format_regex)
      message = error_message || "Parameter '#{param_name}' has invalid format"
      render_validation_error(
        message,
        :invalid_param_format,
        { parameter: param_name, expected_format: format_regex.source }
      )
      return false
    end

    true
  end

  def validate_param_range(param_name, min_value: nil, max_value: nil)
    param_value = params[param_name]
    return true if param_value.blank?

    numeric_value = param_value.to_f

    if min_value && numeric_value < min_value
      render_validation_error(
        "Parameter '#{param_name}' must be at least #{min_value}",
        :param_out_of_range,
        { parameter: param_name, min_value: min_value, provided_value: numeric_value }
      )
      return false
    end

    if max_value && numeric_value > max_value
      render_validation_error(
        "Parameter '#{param_name}' must be at most #{max_value}",
        :param_out_of_range,
        { parameter: param_name, max_value: max_value, provided_value: numeric_value }
      )
      return false
    end

    true
  end

  def validate_enum_param(param_name, allowed_values, case_sensitive: false)
    param_value = params[param_name]
    return true if param_value.blank?

    comparison_values = case_sensitive ? allowed_values : allowed_values.map(&:downcase)
    comparison_param = case_sensitive ? param_value : param_value.downcase

    unless comparison_values.include?(comparison_param)
      render_validation_error(
        "Parameter '#{param_name}' must be one of: #{allowed_values.join(', ')}",
        :invalid_enum_value,
        { parameter: param_name, allowed_values: allowed_values, provided_value: param_value }
      )
      return false
    end

    true
  end

  def validate_array_size(param_name, max_size: nil, min_size: nil)
    param_value = params[param_name]
    return true if param_value.blank?

    array_value = Array(param_value)

    if min_size && array_value.size < min_size
      render_validation_error(
        "Parameter '#{param_name}' must contain at least #{min_size} items",
        :array_too_large,
        { parameter: param_name, min_size: min_size, provided_size: array_value.size }
      )
      return false
    end

    if max_size && array_value.size > max_size
      render_validation_error(
        "Parameter '#{param_name}' cannot contain more than #{max_size} items",
        :array_too_large,
        { parameter: param_name, max_size: max_size, provided_size: array_value.size }
      )
      return false
    end

    true
  end

  def validate_string_length(param_name, max_length: nil, min_length: nil)
    param_value = params[param_name]
    return true if param_value.blank?

    string_value = param_value.to_s

    if min_length && string_value.length < min_length
      render_validation_error(
        "Parameter '#{param_name}' must be at least #{min_length} characters",
        :string_too_long,
        { parameter: param_name, min_length: min_length, provided_length: string_value.length }
      )
      return false
    end

    if max_length && string_value.length > max_length
      render_validation_error(
        "Parameter '#{param_name}' cannot exceed #{max_length} characters",
        :string_too_long,
        { parameter: param_name, max_length: max_length, provided_length: string_value.length }
      )
      return false
    end

    true
  end

  def validate_json_param(param_name)
    param_value = params[param_name]
    return true if param_value.blank?

    if param_value.is_a?(String)
      begin
        JSON.parse(param_value)
      rescue JSON::ParserError => e
        render_validation_error(
          "Parameter '#{param_name}' contains invalid JSON",
          :invalid_json,
          { parameter: param_name, json_error: e.message }
        )
        return false
      end
    end

    true
  end

  # Composite validation methods
  def validate_relic_ids_param
    return false unless validate_required_params(:relic_ids)
    return false unless validate_array_size(:relic_ids, max_size: Rails.application.config.max_relics_per_build, min_size: 1)

    relic_ids = parse_relic_ids

    # Check for duplicates
    if relic_ids.uniq.length != relic_ids.length
      duplicates = relic_ids.group_by(&:itself).select { |_, v| v.length > 1 }.keys
      render_validation_error(
        "Duplicate relic IDs detected",
        :invalid_param_format,
        { duplicate_ids: duplicates }
      )
      return false
    end

    # Validate ID format (assuming UUIDs or similar)
    invalid_ids = relic_ids.reject { |id| id.match?(/\A[\w\-]+\z/) }
    if invalid_ids.any?
      render_validation_error(
        "Invalid relic ID format",
        :invalid_param_format,
        { invalid_ids: invalid_ids }
      )
      return false
    end

    true
  end

  def validate_pagination_params
    if params[:page].present?
      return false unless validate_param_range(:page, min_value: 1)
    end

    if params[:per_page].present?
      return false unless validate_param_range(:per_page, min_value: 1, max_value: Rails.application.config.max_per_page)
    end

    true
  end

  def validate_combat_style_param
    return true if params[:combat_style].blank? && params[:combatStyle].blank?

    combat_style = params[:combat_style] || params[:combatStyle]
    validate_enum_param(:combat_style, Build.combat_styles)
  end

  def validate_context_params
    # Validate combat style if present
    return false unless validate_combat_style_param

    # Validate character level
    if params[:character_level].present? || params[:characterLevel].present?
      level_param = params[:character_level] || params[:characterLevel]
      unless level_param.to_i.between?(1, 999)
        render_validation_error(
          "Character level must be between 1 and 999",
          :param_out_of_range,
          { parameter: "character_level", min_value: 1, max_value: 999 }
        )
        return false
      end
    end

    # Validate JSON parameters
    return false unless validate_json_param(:conditions)
    return false unless validate_json_param(:base_stats)
    return false unless validate_json_param(:baseStats)

    true
  end

  # Error rendering helper
  def render_validation_error(message, error_type, details = {})
    render_error(
      message,
      status: :bad_request,
      error_code: VALIDATION_ERRORS[error_type] || "VALIDATION_ERROR",
      details: details
    )
  end

  # Sanitization methods
  def sanitize_string_param(param_name, max_length: 255)
    param_value = params[param_name]
    return nil if param_value.blank?

    sanitized = param_value.to_s.strip
    sanitized = sanitized[0, max_length] if max_length

    # Remove potentially dangerous characters
    sanitized.gsub(/[<>\"'&]/, "")
  end

  def sanitize_search_query(query)
    return "" if query.blank?

    # Remove SQL injection patterns and limit length
    sanitized = query.to_s.strip[0, 100]
    sanitized.gsub(/[';\"\\]/, "").gsub(/\s+/, " ")
  end

  def sanitize_numeric_param(param_name, default: nil)
    param_value = params[param_name]
    return default if param_value.blank?

    begin
      Float(param_value)
    rescue ArgumentError
      default
    end
  end

  def sanitize_boolean_param(param_name, default: false)
    param_value = params[param_name]
    return default if param_value.blank?

    ActiveModel::Type::Boolean.new.cast(param_value)
  end
end
