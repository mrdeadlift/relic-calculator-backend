class Api::V1::BuildsController < Api::V1::BaseController
  before_action :set_build, only: [:show, :update, :destroy, :clone]
  before_action :validate_build_params, only: [:create, :update]
  
  # GET /api/v1/builds
  def index
    builds = Build.includes(:relics, :build_relics)
    
    # Apply filters
    builds = apply_filters(builds)
    
    # Apply search
    if params[:search].present?
      builds = builds.search(params[:search])
    end
    
    # Apply sorting
    builds = apply_sorting(builds)
    
    # Paginate
    paginated_result = paginate_collection(
      builds,
      per_page: params[:per_page],
      page: params[:page]
    )
    
    render_success(
      paginated_result[:data].map(&:as_json),
      message: 'Builds retrieved successfully',
      meta: paginated_result[:pagination]
    )
  end
  
  # GET /api/v1/builds/:id
  def show
    render_success(
      @build.as_json(
        include: {
          build_relics: {
            include: {
              relic: {
                include: :relic_effects
              }
            }
          }
        }
      ),
      message: 'Build retrieved successfully'
    )
  end
  
  # POST /api/v1/builds
  def create
    @build = Build.new(build_params)
    
    if @build.save
      # Add relics if provided
      if params[:relic_ids].present?
        add_relics_to_build(@build, parse_relic_ids)
      end
      
      render_success(
        @build.as_json,
        message: 'Build created successfully',
        status: :created
      )
    else
      render_validation_errors(@build)
    end
  end
  
  # PATCH/PUT /api/v1/builds/:id
  def update
    if @build.update(build_params)
      # Update relics if provided
      if params[:relic_ids].present?
        update_build_relics(@build, parse_relic_ids)
      end
      
      render_success(
        @build.as_json,
        message: 'Build updated successfully'
      )
    else
      render_validation_errors(@build)
    end
  end
  
  # DELETE /api/v1/builds/:id
  def destroy
    @build.destroy
    
    render_success(
      { deleted_build_id: @build.id },
      message: 'Build deleted successfully'
    )
  end
  
  # POST /api/v1/builds/:id/clone
  def clone
    new_name = params[:name] || "Copy of #{@build.name}"
    user_id = params[:user_id] # For future user system
    
    cloned_build = @build.clone_for_user(user_id, new_name: new_name)
    
    if cloned_build.persisted?
      render_success(
        cloned_build.as_json,
        message: 'Build cloned successfully',
        status: :created
      )
    else
      render_validation_errors(cloned_build)
    end
  end
  
  # POST /api/v1/builds/:id/calculate
  def calculate_build
    context = parse_context_params
    
    # Get relic IDs from the build
    relic_ids = @build.relics.pluck(:id).map(&:to_s)
    
    if relic_ids.empty?
      render_error(
        'Build has no relics to calculate',
        status: :bad_request,
        error_code: 'EMPTY_BUILD'
      )
      return
    end
    
    # Apply build-specific context
    build_context = context.merge(
      'combatStyle' => @build.combat_style
    )
    
    # Validate relics
    RelicValidationService.validate_relic_combination(
      relic_ids,
      context: build_context
    )
    
    # Calculate performance
    calculation_result = CalculationService.calculate_attack_multiplier(
      relic_ids,
      build_context,
      {
        force_recalculate: params[:force_recalculate] == 'true',
        include_breakdown: params[:include_breakdown] != 'false'
      }
    )
    
    render_success(
      {
        build: @build.to_calculation_format,
        calculation: calculation_result,
        performance_summary: {
          total_multiplier: calculation_result[:total_multiplier],
          difficulty_rating: @build.average_difficulty_rating,
          relic_count: relic_ids.length,
          rarity_distribution: @build.rarity_distribution
        }
      },
      message: 'Build calculation completed successfully',
      meta: {
        calculation_context: build_context,
        cached_result: params[:force_recalculate] != 'true'
      }
    )
  end
  
  # POST /api/v1/builds/:id/optimize
  def optimize_build
    constraints = parse_optimization_constraints
    preferences = parse_optimization_preferences
    
    # Get current relic IDs from the build
    current_relic_ids = @build.relics.pluck(:id).map(&:to_s)
    
    if current_relic_ids.empty?
      render_error(
        'Build has no relics to optimize',
        status: :bad_request,
        error_code: 'EMPTY_BUILD'
      )
      return
    end
    
    # Generate optimization suggestions
    optimization_result = OptimizationService.suggest_optimizations(
      current_relic_ids,
      combat_style: @build.combat_style,
      constraints: constraints,
      preferences: preferences
    )
    
    render_success(
      {
        build: @build.to_calculation_format,
        optimization: optimization_result,
        current_performance: optimization_result[:current_rating]
      },
      message: 'Build optimization completed successfully',
      meta: {
        build_id: @build.id,
        combat_style: @build.combat_style,
        suggestion_count: optimization_result[:suggestions]&.length || 0
      }
    )
  end
  
  # POST /api/v1/builds/:id/add_relic
  def add_relic
    relic_id = params[:relic_id]
    position = params[:position]&.to_i
    custom_conditions = parse_custom_conditions
    
    unless relic_id.present?
      render_error(
        'Relic ID is required',
        status: :bad_request,
        error_code: 'MISSING_RELIC_ID'
      )
      return
    end
    
    relic = Relic.find(relic_id)
    
    if @build.add_relic(relic, position: position, custom_conditions: custom_conditions)
      render_success(
        {
          build: @build.reload.as_json,
          added_relic: relic.as_json
        },
        message: 'Relic added to build successfully'
      )
    else
      # Determine specific error reason
      if !@build.can_add_relic?
        render_error(
          "Build is full (max #{Build.max_relics_per_build} relics)",
          status: :bad_request,
          error_code: 'BUILD_FULL'
        )
      elsif @build.has_relic?(relic.id)
        render_error(
          'Relic already exists in build',
          status: :conflict,
          error_code: 'RELIC_ALREADY_EXISTS'
        )
      elsif @build.has_conflicting_relic?(relic)
        conflicting_relics = @build.conflicting_relics_for(relic)
        render_error(
          'Relic conflicts with existing relics in build',
          status: :conflict,
          error_code: 'CONFLICTING_RELICS',
          details: {
            conflicting_relics: conflicting_relics.map { |r| { id: r.id, name: r.name } }
          }
        )
      else
        render_error(
          'Failed to add relic to build',
          status: :bad_request,
          error_code: 'ADD_RELIC_FAILED'
        )
      end
    end
  end
  
  # DELETE /api/v1/builds/:id/remove_relic/:relic_id
  def remove_relic
    relic_id = params[:relic_id]
    
    unless @build.has_relic?(relic_id)
      render_error(
        'Relic not found in build',
        status: :not_found,
        error_code: 'RELIC_NOT_IN_BUILD'
      )
      return
    end
    
    @build.remove_relic(relic_id)
    
    render_success(
      {
        build: @build.reload.as_json,
        removed_relic_id: relic_id
      },
      message: 'Relic removed from build successfully'
    )
  end
  
  # POST /api/v1/builds/:id/reorder_relics
  def reorder_relics
    relic_ids_in_order = parse_relic_ids
    
    # Validate that all relic IDs belong to the build
    build_relic_ids = @build.relics.pluck(:id).map(&:to_s)
    invalid_ids = relic_ids_in_order - build_relic_ids
    
    if invalid_ids.any?
      render_error(
        'Some relic IDs do not belong to this build',
        status: :bad_request,
        error_code: 'INVALID_RELIC_IDS',
        details: { invalid_ids: invalid_ids }
      )
      return
    end
    
    if relic_ids_in_order.length != build_relic_ids.length
      render_error(
        'Must provide all relic IDs in the build for reordering',
        status: :bad_request,
        error_code: 'INCOMPLETE_REORDER_LIST'
      )
      return
    end
    
    @build.reorder_relics(relic_ids_in_order)
    
    render_success(
      @build.reload.as_json,
      message: 'Build relics reordered successfully'
    )
  end
  
  # GET /api/v1/builds/shared/:share_key
  def shared
    build = Build.find_by_share_key(params[:share_key])
    
    unless build
      render_error(
        'Shared build not found',
        status: :not_found,
        error_code: 'SHARED_BUILD_NOT_FOUND'
      )
      return
    end
    
    unless build.is_public?
      render_error(
        'Build is not publicly shared',
        status: :forbidden,
        error_code: 'BUILD_NOT_PUBLIC'
      )
      return
    end
    
    render_success(
      build.to_share_format,
      message: 'Shared build retrieved successfully',
      meta: {
        share_key: params[:share_key],
        share_url: build.generate_share_url
      }
    )
  end
  
  private
  
  def set_build
    @build = Build.includes(:relics, :build_relics).find(params[:id])
  end
  
  def build_params
    params.permit(
      :name, :description, :combat_style, :is_public, :metadata
    )
  end
  
  def validate_build_params
    # Additional validation beyond model validations
    if params[:combat_style].present?
      return unless validate_combat_style!(params[:combat_style])
    end
    
    if params[:relic_ids].present?
      relic_ids = parse_relic_ids
      return unless validate_relic_ids!(relic_ids)
      
      # Check for conflicts in the relic combination
      begin
        RelicValidationService.validate_relic_combination(relic_ids)
      rescue RelicValidationService::ValidationError => e
        render_error(
          e.message,
          status: determine_status_from_error_code(e.error_code),
          error_code: e.error_code,
          details: e.details
        )
        return false
      end
    end
    
    true
  end
  
  def apply_filters(builds)
    # Filter by combat style
    if params[:combat_style].present?
      builds = builds.by_combat_style(params[:combat_style])
    end
    
    # Filter by public/private
    case params[:visibility]
    when 'public'
      builds = builds.public_builds
    when 'private'
      builds = builds.private_builds
    end
    
    # Filter by user (for future user system)
    if params[:user_id].present?
      builds = builds.by_user(params[:user_id])
    end
    
    # Filter by relic count
    if params[:min_relics].present?
      min_relics = params[:min_relics].to_i
      builds = builds.joins(:build_relics)
                     .group('builds.id')
                     .having('COUNT(build_relics.id) >= ?', min_relics)
    end
    
    if params[:max_relics].present?
      max_relics = params[:max_relics].to_i
      builds = builds.joins(:build_relics)
                     .group('builds.id')
                     .having('COUNT(build_relics.id) <= ?', max_relics)
    end
    
    builds
  end
  
  def apply_sorting(builds)
    case params[:sort_by]
    when 'name'
      builds.order(:name)
    when 'created_at'
      builds.order(:created_at)
    when 'updated_at'
      builds.order(:updated_at)
    when 'popularity'
      builds.popular
    else
      builds.recent # Default sorting
    end
  end
  
  def add_relics_to_build(build, relic_ids)
    relics = Relic.where(id: relic_ids)
    
    relics.each_with_index do |relic, index|
      build.add_relic(relic, position: index)
    end
  end
  
  def update_build_relics(build, new_relic_ids)
    current_relic_ids = build.relics.pluck(:id).map(&:to_s)
    
    # Remove relics that are no longer in the list
    to_remove = current_relic_ids - new_relic_ids
    to_remove.each { |relic_id| build.remove_relic(relic_id) }
    
    # Add new relics
    to_add = new_relic_ids - current_relic_ids
    to_add_relics = Relic.where(id: to_add)
    to_add_relics.each { |relic| build.add_relic(relic) }
    
    # Reorder if necessary
    if new_relic_ids != build.reload.relics.pluck(:id).map(&:to_s)
      build.reorder_relics(new_relic_ids)
    end
  end
  
  def parse_custom_conditions
    conditions_param = params[:custom_conditions] || params[:customConditions]
    
    return {} unless conditions_param.present?
    
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
end