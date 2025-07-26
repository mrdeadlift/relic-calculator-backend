class Api::V1::RelicsController < Api::V1::BaseController
  before_action :set_relic, only: [:show]
  
  # GET /api/v1/relics
  def index
    relics = Relic.active.includes(:relic_effects)
    
    # Apply filters
    relics = apply_filters(relics)
    
    # Apply search
    if params[:search].present?
      relics = relics.where(
        "name ILIKE ? OR description ILIKE ?",
        "%#{params[:search]}%",
        "%#{params[:search]}%"
      )
    end
    
    # Apply sorting
    relics = apply_sorting(relics)
    
    # Paginate
    paginated_result = paginate_collection(
      relics,
      per_page: params[:per_page],
      page: params[:page]
    )
    
    render_paginated_collection(
      paginated_result[:data],
      paginated_result[:pagination],
      message: 'Relics retrieved successfully'
    )
  end
  
  # GET /api/v1/relics/:id
  def show
    render_success(
      @relic.as_json(include: { relic_effects: { except: [:created_at, :updated_at] } }),
      message: 'Relic retrieved successfully'
    )
  end
  
  # POST /api/v1/relics/calculate
  def calculate
    relic_ids = parse_relic_ids
    context = parse_context_params
    
    return unless validate_relic_ids!(relic_ids)
    return unless validate_combat_style!(context['combatStyle'])
    
    # Validate relics exist and are compatible
    RelicValidationService.validate_relic_combination(
      relic_ids,
      context: context,
      strict_mode: params[:strict_mode] == 'true'
    )
    
    # Perform calculation
    calculation_result = CalculationService.calculate_attack_multiplier(
      relic_ids,
      context,
      {
        force_recalculate: params[:force_recalculate] == 'true',
        include_breakdown: params[:include_breakdown] != 'false'
      }
    )
    
    serialized_result = CalculationResultSerializer.new(calculation_result).as_json
    
    render_success(
      serialized_result,
      message: 'Attack multiplier calculated successfully',
      meta: {
        calculation_context: context,
        input_relic_count: relic_ids.length,
        cached_result: params[:force_recalculate] != 'true'
      }
    )
  end
  
  # POST /api/v1/relics/validate
  def validate_combination
    relic_ids = parse_relic_ids
    context = parse_context_params
    
    return unless validate_relic_ids!(relic_ids)
    
    # Perform validation with preprocessing
    validation_result = RelicValidationService.preprocess_relics_for_calculation(
      relic_ids,
      context: context
    )
    
    render_success(
      validation_result,
      message: 'Relic combination validated successfully',
      meta: {
        validation_context: context,
        strict_mode: params[:strict_mode] == 'true'
      }
    )
  end
  
  # POST /api/v1/relics/compare
  def compare_combinations
    combinations = parse_comparison_combinations
    
    if combinations.empty?
      render_error(
        'At least one combination is required for comparison',
        status: :bad_request,
        error_code: 'EMPTY_COMBINATIONS_LIST'
      )
      return
    end
    
    if combinations.length > 10
      render_error(
        'Too many combinations for comparison (max: 10)',
        status: :bad_request,
        error_code: 'TOO_MANY_COMBINATIONS',
        details: { max_combinations: 10, provided_count: combinations.length }
      )
      return
    end
    
    # Validate each combination
    combinations.each_with_index do |combination, index|
      unless validate_relic_ids!(combination[:relic_ids])
        render_error(
          "Invalid relic IDs in combination #{index + 1}",
          status: :bad_request,
          error_code: 'INVALID_COMBINATION'
        )
        return
      end
    end
    
    # Perform comparison
    comparison_result = OptimizationService.compare_builds(
      combinations,
      comparison_mode: params[:comparison_mode] || 'simple'
    )
    
    render_success(
      comparison_result,
      message: 'Build combinations compared successfully',
      meta: {
        total_combinations: combinations.length,
        comparison_mode: params[:comparison_mode] || 'simple'
      }
    )
  end
  
  # GET /api/v1/relics/categories
  def categories
    categories = Relic.active.distinct.pluck(:category).compact.sort
    
    category_counts = Relic.active.group(:category).count
    
    categories_with_counts = categories.map do |category|
      {
        name: category,
        count: category_counts[category] || 0,
        display_name: category.humanize
      }
    end
    
    render_success(
      categories_with_counts,
      message: 'Relic categories retrieved successfully'
    )
  end
  
  # GET /api/v1/relics/rarities
  def rarities
    rarities = Relic.active.distinct.pluck(:rarity).compact.sort
    
    rarity_counts = Relic.active.group(:rarity).count
    
    rarities_with_counts = rarities.map do |rarity|
      {
        name: rarity,
        count: rarity_counts[rarity] || 0,
        display_name: rarity.humanize
      }
    end
    
    render_success(
      rarities_with_counts,
      message: 'Relic rarities retrieved successfully'
    )
  end
  
  private
  
  def set_relic
    @relic = Relic.active.includes(:relic_effects).find(params[:id])
  end
  
  def apply_filters(relics)
    # Filter by category
    if params[:category].present?
      categories = parse_string_array(params[:category])
      relics = relics.where(category: categories)
    end
    
    # Filter by rarity
    if params[:rarity].present?
      rarities = parse_string_array(params[:rarity])
      relics = relics.where(rarity: rarities)
    end
    
    # Filter by quality
    if params[:quality].present?
      qualities = parse_string_array(params[:quality])
      relics = relics.where(quality: qualities)
    end
    
    # Filter by difficulty range
    if params[:min_difficulty].present?
      relics = relics.where('obtainment_difficulty >= ?', params[:min_difficulty].to_i)
    end
    
    if params[:max_difficulty].present?
      relics = relics.where('obtainment_difficulty <= ?', params[:max_difficulty].to_i)
    end
    
    # Filter by effect type
    if params[:effect_type].present?
      effect_types = parse_string_array(params[:effect_type])
      relics = relics.joins(:relic_effects)
                     .where(relic_effects: { effect_type: effect_types })
                     .distinct
    end
    
    relics
  end
  
  def apply_sorting(relics)
    case params[:sort_by]
    when 'name'
      relics.order(:name)
    when 'rarity'
      relics.order(:rarity, :name)
    when 'difficulty'
      relics.order(:obtainment_difficulty, :name)
    when 'created_at'
      relics.order(:created_at)
    else
      relics.order(:name) # Default sorting
    end
  end
  
  def parse_comparison_combinations
    combinations_param = params[:combinations]
    
    return [] unless combinations_param.present?
    
    case combinations_param
    when String
      begin
        parsed = JSON.parse(combinations_param)
        Array(parsed)
      rescue JSON::ParserError
        []
      end
    when Array
      combinations_param
    else
      []
    end.map do |combination|
      {
        build_id: combination['build_id'] || combination['buildId'],
        name: combination['name'],
        relic_ids: Array(combination['relic_ids'] || combination['relicIds']).map(&:to_s),
        context: combination['context'] || {},
        combat_style: combination['combat_style'] || combination['combatStyle'] || 'melee'
      }
    end
  end
end