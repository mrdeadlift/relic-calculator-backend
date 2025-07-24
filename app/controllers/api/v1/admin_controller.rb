class Api::V1::AdminController < Api::V1::BaseController
  # TODO: Add authentication/authorization middleware for admin access
  # before_action :authenticate_admin!
  
  # POST /api/v1/admin/relics
  def create_relic
    relic_params = parse_relic_params
    
    return unless validate_admin_relic_params!(relic_params)
    
    @relic = Relic.new(relic_params.except(:effects))
    
    if @relic.save
      # Add effects if provided
      if relic_params[:effects].present?
        add_effects_to_relic(@relic, relic_params[:effects])
      end
      
      render_success(
        @relic.as_json(include: :relic_effects),
        message: 'Relic created successfully',
        status: :created,
        meta: {
          relic_id: @relic.id,
          effects_count: @relic.relic_effects.count
        }
      )
    else
      render_validation_errors(@relic)
    end
  end
  
  # PUT /api/v1/admin/relics/:id
  def update_relic
    @relic = Relic.find(params[:id])
    relic_params = parse_relic_params
    
    return unless validate_admin_relic_params!(relic_params)
    
    if @relic.update(relic_params.except(:effects))
      # Update effects if provided
      if relic_params[:effects].present?
        update_relic_effects(@relic, relic_params[:effects])
      end
      
      render_success(
        @relic.reload.as_json(include: :relic_effects),
        message: 'Relic updated successfully',
        meta: {
          relic_id: @relic.id,
          effects_count: @relic.relic_effects.count
        }
      )
    else
      render_validation_errors(@relic)
    end
  end
  
  # DELETE /api/v1/admin/relics/:id
  def delete_relic
    @relic = Relic.find(params[:id])
    
    # Check if relic is used in builds
    builds_using_relic = Build.joins(:relics).where(relics: { id: @relic.id })
    
    if builds_using_relic.exists? && params[:force] != 'true'
      render_error(
        'Relic is used in existing builds. Use force=true to delete anyway.',
        status: :conflict,
        error_code: 'RELIC_IN_USE',
        details: {
          builds_count: builds_using_relic.count,
          build_ids: builds_using_relic.limit(10).pluck(:id)
        }
      )
      return
    end
    
    # Remove from builds if forced
    if params[:force] == 'true'
      builds_using_relic.each do |build|
        build.remove_relic(@relic.id)
      end
    end
    
    deleted_relic_data = {
      id: @relic.id,
      name: @relic.name,
      effects_count: @relic.relic_effects.count
    }
    
    @relic.destroy
    
    render_success(
      {
        deleted_relic: deleted_relic_data,
        builds_updated: builds_using_relic.count
      },
      message: 'Relic deleted successfully'
    )
  end
  
  # POST /api/v1/admin/relics/validate
  def validate_data
    check_type = params[:check_type] || 'all'
    
    validation_results = case check_type
                        when 'consistency'
                          validate_data_consistency
                        when 'conflicts'
                          validate_relic_conflicts
                        when 'balance'
                          validate_game_balance
                        when 'all'
                          {
                            consistency: validate_data_consistency,
                            conflicts: validate_relic_conflicts,
                            balance: validate_game_balance
                          }
                        else
                          render_error(
                            'Invalid check_type. Use: consistency, conflicts, balance, or all',
                            status: :bad_request,
                            error_code: 'INVALID_CHECK_TYPE'
                          )
                          return
                        end
    
    # Generate summary
    all_issues = []
    if validation_results.is_a?(Hash) && validation_results.key?(:consistency)
      validation_results.each_value { |result| all_issues.concat(result[:issues]) }
    else
      all_issues = validation_results[:issues]
    end
    
    critical_issues = all_issues.count { |issue| issue[:type] == 'error' }
    
    render_success(
      {
        results: validation_results,
        summary: {
          total_relics: Relic.count,
          total_issues: all_issues.count,
          critical_issues: critical_issues,
          is_valid: critical_issues == 0
        }
      },
      message: 'Data validation completed',
      meta: {
        check_type: check_type,
        validation_timestamp: Time.current
      }
    )
  end
  
  # POST /api/v1/admin/relics/import
  def import_relics
    import_data = params[:import_data]
    import_format = params[:format] || 'json'
    
    unless import_data.present?
      render_error(
        'Import data is required',
        status: :bad_request,
        error_code: 'MISSING_IMPORT_DATA'
      )
      return
    end
    
    begin
      parsed_data = case import_format
                   when 'json'
                     JSON.parse(import_data)
                   when 'csv'
                     parse_csv_relics(import_data)
                   else
                     render_error(
                       'Unsupported import format. Use json or csv',
                       status: :bad_request,
                       error_code: 'UNSUPPORTED_FORMAT'
                     )
                     return
                   end
      
      import_results = import_relics_data(parsed_data)
      
      render_success(
        import_results,
        message: 'Relic import completed',
        meta: {
          import_format: import_format,
          import_timestamp: Time.current
        }
      )
    rescue JSON::ParserError => e
      render_error(
        "Invalid JSON format: #{e.message}",
        status: :bad_request,
        error_code: 'INVALID_JSON'
      )
    rescue => e
      render_error(
        "Import failed: #{e.message}",
        status: :internal_server_error,
        error_code: 'IMPORT_FAILED'
      )
    end
  end
  
  # GET /api/v1/admin/relics/export
  def export_relics
    export_format = params[:format] || 'json'
    include_effects = params[:include_effects] != 'false'
    
    relics = Relic.all
    relics = relics.includes(:relic_effects) if include_effects
    
    export_data = case export_format
                 when 'json'
                   export_relics_json(relics, include_effects)
                 when 'csv'
                   export_relics_csv(relics, include_effects)
                 else
                   render_error(
                     'Unsupported export format. Use json or csv',
                     status: :bad_request,
                     error_code: 'UNSUPPORTED_FORMAT'
                   )
                   return
                 end
    
    render_success(
      {
        format: export_format,
        data: export_data,
        metadata: {
          exported_at: Time.current,
          relic_count: relics.count,
          include_effects: include_effects
        }
      },
      message: 'Relic export completed'
    )
  end
  
  # GET /api/v1/admin/statistics
  def statistics
    stats = {
      relics: {
        total: Relic.count,
        active: Relic.active.count,
        inactive: Relic.inactive.count,
        by_category: Relic.group(:category).count,
        by_rarity: Relic.group(:rarity).count,
        by_quality: Relic.group(:quality).count
      },
      effects: {
        total: RelicEffect.count,
        active: RelicEffect.active.count,
        by_type: RelicEffect.group(:effect_type).count,
        by_stacking_rule: RelicEffect.group(:stacking_rule).count
      },
      builds: {
        total: Build.count,
        public: Build.where(is_public: true).count,
        private: Build.where(is_public: false).count,
        with_share_key: Build.where.not(share_key: nil).count,
        by_combat_style: Build.group(:combat_style).count
      },
      cache: CalculationCache.cache_statistics
    }
    
    render_success(
      stats,
      message: 'Statistics retrieved successfully',
      meta: {
        generated_at: Time.current,
        version: Rails.application.class.module_parent_name
      }
    )
  end
  
  private
  
  def parse_relic_params
    permitted_params = params.permit(
      :name, :description, :category, :rarity, :quality, :icon_url,
      :obtainment_difficulty, :active, conflicts: [],
      effects: [:effect_type, :name, :description, :value, :stacking_rule,
                :priority, :active, damage_types: [], conditions: []]
    )
    
    # Parse JSON fields
    if params[:conflicts].is_a?(String)
      begin
        permitted_params[:conflicts] = JSON.parse(params[:conflicts])
      rescue JSON::ParserError
        permitted_params[:conflicts] = []
      end
    end
    
    if params[:effects].is_a?(String)
      begin
        permitted_params[:effects] = JSON.parse(params[:effects])
      rescue JSON::ParserError
        permitted_params[:effects] = []
      end
    end
    
    permitted_params
  end
  
  def validate_admin_relic_params!(relic_params)
    errors = []
    
    # Validate required fields
    errors << 'Name is required' unless relic_params[:name].present?
    errors << 'Description is required' unless relic_params[:description].present?
    errors << 'Category is required' unless relic_params[:category].present?
    
    # Validate enums
    unless Relic.categories.include?(relic_params[:category])
      errors << "Invalid category. Must be one of: #{Relic.categories.join(', ')}"
    end
    
    unless Relic.rarities.include?(relic_params[:rarity])
      errors << "Invalid rarity. Must be one of: #{Relic.rarities.join(', ')}"
    end
    
    unless Relic.qualities.include?(relic_params[:quality])
      errors << "Invalid quality. Must be one of: #{Relic.qualities.join(', ')}"
    end
    
    # Validate difficulty range
    difficulty = relic_params[:obtainment_difficulty].to_i
    unless Relic.difficulty_range.include?(difficulty)
      errors << "Obtainment difficulty must be between #{Relic.difficulty_range.first} and #{Relic.difficulty_range.last}"
    end
    
    if errors.any?
      render_error(
        errors.join('; '),
        status: :bad_request,
        error_code: 'VALIDATION_ERROR',
        details: { validation_errors: errors }
      )
      return false
    end
    
    true
  end
  
  def add_effects_to_relic(relic, effects_data)
    effects_data.each do |effect_data|
      relic.relic_effects.create!(
        effect_type: effect_data[:effect_type],
        name: effect_data[:name],
        description: effect_data[:description],
        value: effect_data[:value],
        stacking_rule: effect_data[:stacking_rule] || 'additive',
        conditions: effect_data[:conditions] || [],
        damage_types: effect_data[:damage_types] || [],
        priority: effect_data[:priority] || 1,
        active: effect_data[:active] != false
      )
    end
  end
  
  def update_relic_effects(relic, effects_data)
    # Remove existing effects
    relic.relic_effects.destroy_all
    
    # Add new effects
    add_effects_to_relic(relic, effects_data)
  end
  
  def validate_data_consistency
    issues = []
    
    # Check for orphaned effects
    orphaned_effects = RelicEffect.left_joins(:relic).where(relics: { id: nil })
    if orphaned_effects.exists?
      issues << {
        type: 'error',
        code: 'ORPHANED_EFFECTS',
        message: "Found #{orphaned_effects.count} relic effects without parent relics",
        affected_items: orphaned_effects.pluck(:id)
      }
    end
    
    # Check for missing required fields
    relics_missing_description = Relic.where(description: [nil, ''])
    if relics_missing_description.exists?
      issues << {
        type: 'warning',
        code: 'MISSING_DESCRIPTIONS',
        message: "Found #{relics_missing_description.count} relics without descriptions",
        affected_items: relics_missing_description.pluck(:id)
      }
    end
    
    # Check for duplicate names
    duplicate_names = Relic.group(:name).having('COUNT(*) > 1').pluck(:name)
    if duplicate_names.any?
      issues << {
        type: 'error',
        code: 'DUPLICATE_NAMES',
        message: "Found #{duplicate_names.length} duplicate relic names",
        affected_items: duplicate_names
      }
    end
    
    { issues: issues, checked_at: Time.current }
  end
  
  def validate_relic_conflicts
    issues = []
    
    # Check for self-referencing conflicts
    self_conflicting = Relic.where("conflicts ? id::text")
    if self_conflicting.exists?
      issues << {
        type: 'error',
        code: 'SELF_CONFLICTS',
        message: "Found #{self_conflicting.count} relics that conflict with themselves",
        affected_items: self_conflicting.pluck(:id)
      }
    end
    
    # Check for non-existent conflict references
    all_relic_ids = Relic.pluck(:id).map(&:to_s)
    Relic.where.not(conflicts: nil).find_each do |relic|
      invalid_conflicts = relic.conflicts - all_relic_ids
      if invalid_conflicts.any?
        issues << {
          type: 'warning',
          code: 'INVALID_CONFLICT_REFERENCES',
          message: "Relic #{relic.name} references non-existent conflict IDs: #{invalid_conflicts.join(', ')}",
          affected_items: [relic.id]
        }
      end
    end
    
    { issues: issues, checked_at: Time.current }
  end
  
  def validate_game_balance
    issues = []
    
    # Check for overpowered combinations
    high_multiplier_relics = Relic.joins(:relic_effects)
                                 .where(relic_effects: { effect_type: 'attack_multiplier' })
                                 .where('relic_effects.value > ?', 50)
    
    if high_multiplier_relics.exists?
      issues << {
        type: 'warning',
        code: 'HIGH_MULTIPLIERS',
        message: "Found #{high_multiplier_relics.count} relics with very high attack multipliers (>50%)",
        affected_items: high_multiplier_relics.pluck(:id)
      }
    end
    
    # Check difficulty vs power balance
    easy_legendary = Relic.where(rarity: 'legendary', obtainment_difficulty: 1..3)
    if easy_legendary.exists?
      issues << {
        type: 'warning',
        code: 'EASY_LEGENDARIES',
        message: "Found #{easy_legendary.count} legendary relics with low difficulty rating",
        affected_items: easy_legendary.pluck(:id)
      }
    end
    
    { issues: issues, checked_at: Time.current }
  end
  
  def import_relics_data(data)
    successful_imports = 0
    failed_imports = []
    
    Array(data).each_with_index do |relic_data, index|
      begin
        relic = Relic.create!(
          name: relic_data['name'],
          description: relic_data['description'],
          category: relic_data['category'],
          rarity: relic_data['rarity'],
          quality: relic_data['quality'],
          icon_url: relic_data['icon_url'],
          obtainment_difficulty: relic_data['obtainment_difficulty'],
          conflicts: relic_data['conflicts'] || [],
          active: relic_data['active'] != false
        )
        
        # Add effects if present
        if relic_data['effects'].present?
          add_effects_to_relic(relic, relic_data['effects'])
        end
        
        successful_imports += 1
      rescue => e
        failed_imports << {
          index: index,
          name: relic_data['name'],
          error: e.message
        }
      end
    end
    
    {
      successful_imports: successful_imports,
      failed_imports: failed_imports,
      total_processed: Array(data).length
    }
  end
  
  def export_relics_json(relics, include_effects)
    relics.map do |relic|
      relic_data = relic.attributes.except('created_at', 'updated_at')
      relic_data['effects'] = relic.relic_effects.map(&:attributes) if include_effects
      relic_data
    end
  end
  
  def export_relics_csv(relics, include_effects)
    # Simplified CSV export - would need proper CSV handling in production
    headers = %w[id name description category rarity quality icon_url obtainment_difficulty conflicts active]
    headers << 'effects_count' if include_effects
    
    csv_data = [headers.join(',')]
    
    relics.each do |relic|
      row = [
        relic.id,
        "\"#{relic.name}\"",
        "\"#{relic.description}\"",
        relic.category,
        relic.rarity,
        relic.quality,
        relic.icon_url,
        relic.obtainment_difficulty,
        "\"#{relic.conflicts&.join(';')}\"",
        relic.active
      ]
      row << relic.relic_effects.count if include_effects
      csv_data << row.join(',')
    end
    
    csv_data.join("\n")
  end
  
  def parse_csv_relics(csv_data)
    # Simplified CSV parsing - would use proper CSV library in production
    lines = csv_data.split("\n")
    headers = lines.first.split(',')
    
    lines[1..-1].map do |line|
      values = line.split(',')
      Hash[headers.zip(values)]
    end
  end
end