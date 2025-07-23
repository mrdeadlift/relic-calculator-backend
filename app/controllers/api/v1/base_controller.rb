class Api::V1::BaseController < ApplicationController
  before_action :set_api_version
  
  private
  
  def set_api_version
    @api_version = 'v1'
  end
  
  def default_meta
    super.merge(api_version: @api_version)
  end
  
  # Pagination helpers
  def paginate_collection(collection, per_page: 20, page: 1)
    page = [page.to_i, 1].max
    per_page = [[per_page.to_i, 1].max, 100].min # Limit max per_page to 100
    
    paginated = collection.page(page).per(per_page)
    
    {
      data: paginated,
      pagination: {
        current_page: paginated.current_page,
        per_page: paginated.limit_value,
        total_pages: paginated.total_pages,
        total_count: paginated.total_count,
        has_next_page: paginated.current_page < paginated.total_pages,
        has_prev_page: paginated.current_page > 1
      }
    }
  end
  
  # Parameter parsing helpers
  def parse_relic_ids
    relic_ids = params[:relic_ids] || params[:relicIds]
    
    case relic_ids
    when String
      relic_ids.split(',').map(&:strip)
    when Array
      relic_ids.map(&:to_s)
    else
      []
    end
  end
  
  def parse_context_params
    context = {}
    
    context['combatStyle'] = params[:combat_style] || params[:combatStyle] if params[:combat_style] || params[:combatStyle]
    context['weaponType'] = params[:weapon_type] || params[:weaponType] if params[:weapon_type] || params[:weaponType]
    context['characterLevel'] = params[:character_level]&.to_i || params[:characterLevel]&.to_i if params[:character_level] || params[:characterLevel]
    
    # Parse conditions
    if params[:conditions].present?
      context['conditions'] = parse_conditions(params[:conditions])
    end
    
    # Parse base stats
    if params[:base_stats].present? || params[:baseStats].present?
      base_stats = params[:base_stats] || params[:baseStats]
      context['baseStats'] = parse_base_stats(base_stats)
    end
    
    context.compact
  end
  
  def parse_conditions(conditions_param)
    case conditions_param
    when String
      begin
        JSON.parse(conditions_param)
      rescue JSON::ParserError
        {}
      end
    when Hash
      conditions_param
    else
      {}
    end
  end
  
  def parse_base_stats(base_stats_param)
    case base_stats_param
    when String
      begin
        JSON.parse(base_stats_param)
      rescue JSON::ParserError
        {}
      end
    when Hash
      base_stats_param
    else
      {}
    end
  end
  
  def parse_optimization_constraints
    constraints = {}
    
    if params[:max_difficulty].present? || params[:maxDifficulty].present?
      constraints['maxDifficulty'] = (params[:max_difficulty] || params[:maxDifficulty]).to_i
    end
    
    if params[:allowed_categories].present? || params[:allowedCategories].present?
      categories = params[:allowed_categories] || params[:allowedCategories]
      constraints['allowedCategories'] = parse_string_array(categories)
    end
    
    if params[:exclude_relic_ids].present? || params[:excludeRelicIds].present?
      exclude_ids = params[:exclude_relic_ids] || params[:excludeRelicIds]
      constraints['excludeRelicIds'] = parse_string_array(exclude_ids)
    end
    
    constraints
  end
  
  def parse_optimization_preferences
    preferences = {}
    
    if params[:prefer_high_rarity].present? || params[:preferHighRarity].present?
      preferences['preferHighRarity'] = ActiveModel::Type::Boolean.new.cast(
        params[:prefer_high_rarity] || params[:preferHighRarity]
      )
    end
    
    if params[:prefer_low_difficulty].present? || params[:preferLowDifficulty].present?
      preferences['preferLowDifficulty'] = ActiveModel::Type::Boolean.new.cast(
        params[:prefer_low_difficulty] || params[:preferLowDifficulty]
      )
    end
    
    if params[:min_improvement].present? || params[:minImprovement].present?
      preferences['minImprovement'] = (params[:min_improvement] || params[:minImprovement]).to_f
    end
    
    preferences
  end
  
  def parse_string_array(value)
    case value
    when String
      value.split(',').map(&:strip)
    when Array
      value.map(&:to_s)
    else
      []
    end
  end
  
  # Validation helpers
  def validate_required_params!(*required_params)
    missing_params = required_params.select { |param| params[param].blank? }
    
    if missing_params.any?
      raise ActionController::ParameterMissing.new(missing_params.first)
    end
  end
  
  def validate_relic_ids!(relic_ids)
    if relic_ids.empty?
      render_error(
        'At least one relic ID is required',
        status: :bad_request,
        error_code: 'EMPTY_RELIC_LIST'
      )
      return false
    end
    
    if relic_ids.length > Build.max_relics_per_build
      render_error(
        "Too many relics provided (max: #{Build.max_relics_per_build})",
        status: :bad_request,
        error_code: 'RELIC_LIMIT_EXCEEDED',
        details: { 
          max_relics: Build.max_relics_per_build,
          provided_count: relic_ids.length 
        }
      )
      return false
    end
    
    true
  end
  
  def validate_combat_style!(combat_style)
    return true if combat_style.blank?
    
    unless Build.combat_styles.include?(combat_style)
      render_error(
        "Invalid combat style: #{combat_style}",
        status: :bad_request,
        error_code: 'INVALID_COMBAT_STYLE',
        details: { valid_styles: Build.combat_styles }
      )
      return false
    end
    
    true
  end
end