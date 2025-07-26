class CalculationService
  include ActiveModel::Model
  include ActiveModel::Attributes
  
  # Custom error classes
  class CalculationError < StandardError
    attr_reader :details, :error_code
    
    def initialize(message, details: {}, error_code: 'CALCULATION_ERROR')
      super(message)
      @details = details
      @error_code = error_code
    end
  end
  
  class TimeoutError < CalculationError
    def initialize(message = 'Calculation timed out')
      super(message, error_code: 'CALCULATION_TIMEOUT')
    end
  end
  
  class InvalidContextError < CalculationError
    def initialize(message = 'Invalid calculation context')
      super(message, error_code: 'INVALID_CALCULATION_CONTEXT')
    end
  end
  
  # Attributes
  attribute :relic_ids, default: -> { [] }
  attribute :context, default: -> { {} }
  attribute :base_stats, default: -> { {} }
  attribute :options, default: -> { {} }
  
  # Constants
  DEFAULT_BASE_ATTACK = 100.0
  DEFAULT_CHARACTER_LEVEL = 1
  CALCULATION_TIMEOUT = 5.seconds
  MAX_RELICS = 9
  
  # Class methods
  def self.calculate_attack_multiplier(relic_ids, context = {}, options = {})
    service = new(
      relic_ids: Array(relic_ids),
      context: context,
      options: options
    )
    
    service.calculate
  end
  
  def self.validate_relic_combination(relic_ids)
    relics = Relic.where(id: relic_ids).includes(:relic_effects)
    
    if relics.count != relic_ids.length
      missing_ids = relic_ids - relics.pluck(:id).map(&:to_s)
      raise CalculationError.new(
        "Relics not found: #{missing_ids.join(', ')}",
        details: { missing_relic_ids: missing_ids },
        error_code: 'RELIC_NOT_FOUND'
      )
    end
    
    # Check for conflicts
    conflicts = find_conflicts(relics)
    if conflicts.any?
      raise CalculationError.new(
        "Conflicting relics detected",
        details: { conflicts: conflicts },
        error_code: 'CONFLICTING_RELICS'
      )
    end
    
    relics
  end
  
  def self.find_conflicts(relics)
    conflicts = []
    relic_ids = relics.map(&:id).map(&:to_s)
    
    relics.each do |relic|
      next unless relic.has_conflicts?
      
      conflicting_ids = relic.conflicts & relic_ids
      if conflicting_ids.any?
        conflicts << {
          relic_id: relic.id.to_s,
          relic_name: relic.name,
          conflicting_ids: conflicting_ids
        }
      end
    end
    
    conflicts
  end
  
  # Instance methods
  def calculate
    validate_inputs!
    
    # Use cache if available
    cache_key = generate_cache_key
    cached_result = CalculationCache.find_cached_result(cache_key)
    
    if cached_result && !options[:force_recalculate]
      return parse_cached_result(cached_result.result_data)
    end
    
    # Perform calculation with timeout
    result = nil
    
    Timeout.timeout(CALCULATION_TIMEOUT) do
      result = perform_calculation
    end
    
    # Cache the result
    cache_result(cache_key, result) if result
    
    result
  rescue Timeout::Error
    raise TimeoutError.new
  rescue => e
    Rails.logger.error "Calculation failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    if e.is_a?(CalculationError)
      raise e
    else
      raise CalculationError.new("Unexpected calculation error: #{e.message}")
    end
  end
  
  private
  
  def validate_inputs!
    if relic_ids.length > MAX_RELICS
      raise CalculationError.new(
        "Too many relics selected (max: #{MAX_RELICS})",
        details: { max_relics: MAX_RELICS, selected_count: relic_ids.length },
        error_code: 'SELECTION_LIMIT_EXCEEDED'
      )
    end
    
    if context.blank?
      raise InvalidContextError.new("Calculation context is required")
    end
    
    unless context.is_a?(Hash)
      raise InvalidContextError.new("Context must be a hash")
    end
  end
  
  def perform_calculation
    relics = self.class.validate_relic_combination(relic_ids)
    
    # Initialize calculation state
    calculation_state = initialize_calculation_state(relics)
    
    # Apply base stats
    apply_base_stats(calculation_state)
    
    # Process effects by priority and stacking rules
    process_relic_effects(calculation_state, relics)
    
    # Generate detailed breakdown
    generate_result(calculation_state)
  end
  
  def initialize_calculation_state(relics)
    {
      base_attack: extract_base_attack,
      current_multiplier: 1.0,
      flat_bonuses: 0.0,
      percentage_bonuses: 0.0,
      multiplicative_bonuses: 1.0,
      conditional_effects: [],
      stacking_bonuses: [],
      breakdown: [],
      warnings: [],
      errors: [],
      context: normalize_context,
      relics: relics,
      damage_by_type: initialize_damage_types
    }
  end
  
  def extract_base_attack
    base_stats.dig('attackPower')&.to_f || 
    context.dig('baseStats', 'attackPower')&.to_f || 
    DEFAULT_BASE_ATTACK
  end
  
  def normalize_context
    normalized = context.deep_dup
    normalized['combatStyle'] ||= 'melee'
    normalized['characterLevel'] ||= DEFAULT_CHARACTER_LEVEL
    normalized['conditions'] ||= {}
    normalized
  end
  
  def initialize_damage_types
    %w[physical magical fire ice lightning dark holy].each_with_object({}) do |type, hash|
      hash[type] = 0.0
    end
  end
  
  def apply_base_stats(state)
    add_breakdown_step(state, {
      step: state[:breakdown].length + 1,
      description: "Base attack power",
      operation: 'base',
      value: state[:base_attack],
      running_total: state[:base_attack]
    })
  end
  
  def process_relic_effects(state, relics)
    # Collect all effects and sort by priority
    all_effects = []
    
    relics.each do |relic|
      relic.relic_effects.active.each do |effect|
        all_effects << {
          effect: effect,
          relic: relic,
          relic_name: relic.name
        }
      end
    end
    
    # Group effects by stacking rule and process them
    grouped_effects = all_effects.group_by { |item| item[:effect].stacking_rule }
    
    # Process in specific order: additive first, then multiplicative
    %w[additive multiplicative overwrite unique].each do |stacking_rule|
      next unless grouped_effects[stacking_rule]
      
      process_stacking_group(state, grouped_effects[stacking_rule], stacking_rule)
    end
  end
  
  def process_stacking_group(state, effect_items, stacking_rule)
    case stacking_rule
    when 'additive'
      process_additive_effects(state, effect_items)
    when 'multiplicative'
      process_multiplicative_effects(state, effect_items)
    when 'overwrite'
      process_overwrite_effects(state, effect_items)
    when 'unique'
      process_unique_effects(state, effect_items)
    end
  end
  
  def process_additive_effects(state, effect_items)
    # Group by effect type for proper stacking
    grouped_by_type = effect_items.group_by { |item| item[:effect].effect_type }
    
    grouped_by_type.each do |effect_type, items|
      total_value = 0.0
      active_effects = []
      
      items.each do |item|
        effect = item[:effect]
        
        if effect_applies?(effect, state[:context])
          effective_value = calculate_effective_value(effect, state)
          total_value += effective_value
          
          active_effects << create_stacking_bonus(item, effective_value, total_value)
        end
      end
      
      if total_value > 0
        apply_additive_bonus(state, effect_type, total_value, active_effects)
      end
    end
  end
  
  def process_multiplicative_effects(state, effect_items)
    effect_items.each do |item|
      effect = item[:effect]
      
      next unless effect_applies?(effect, state[:context])
      
      effective_value = calculate_effective_value(effect, state)
      multiplier = convert_to_multiplier(effect, effective_value)
      
      state[:multiplicative_bonuses] *= multiplier
      
      stacking_bonus = create_stacking_bonus(item, effective_value, multiplier)
      state[:stacking_bonuses] << stacking_bonus
      
      add_breakdown_step(state, {
        step: state[:breakdown].length + 1,
        description: "#{effect.name} (#{item[:relic_name]})",
        operation: 'multiply',
        value: multiplier,
        running_total: state[:base_attack] * state[:multiplicative_bonuses],
        relic_name: item[:relic_name],
        effect_name: effect.name
      })
    end
  end
  
  def process_overwrite_effects(state, effect_items)
    # For overwrite effects, only the highest priority takes effect
    active_effect = effect_items
      .select { |item| effect_applies?(item[:effect], state[:context]) }
      .max_by { |item| item[:effect].priority }
    
    return unless active_effect
    
    effect = active_effect[:effect]
    effective_value = calculate_effective_value(effect, state)
    
    # Apply the overwrite effect
    case effect.effect_type
    when 'attack_flat'
      state[:flat_bonuses] = effective_value
    when 'attack_percentage'
      state[:percentage_bonuses] = effective_value
    when 'attack_multiplier'
      state[:multiplicative_bonuses] = convert_to_multiplier(effect, effective_value)
    end
    
    stacking_bonus = create_stacking_bonus(active_effect, effective_value, effective_value)
    state[:stacking_bonuses] << stacking_bonus
    
    add_breakdown_step(state, {
      step: state[:breakdown].length + 1,
      description: "#{effect.name} (#{active_effect[:relic_name]}) - Overwrite",
      operation: 'overwrite',
      value: effective_value,
      running_total: calculate_current_total(state),
      relic_name: active_effect[:relic_name],
      effect_name: effect.name
    })
  end
  
  def process_unique_effects(state, effect_items)
    # Unique effects don't stack, but multiple unique effects can coexist
    effect_items.each do |item|
      effect = item[:effect]
      
      next unless effect_applies?(effect, state[:context])
      
      effective_value = calculate_effective_value(effect, state)
      
      # Apply unique effect based on its type
      apply_unique_effect(state, effect, effective_value, item)
      
      stacking_bonus = create_stacking_bonus(item, effective_value, effective_value)
      stacking_bonus[:stacking_rule] = 'unique'
      state[:stacking_bonuses] << stacking_bonus
    end
  end
  
  def effect_applies?(effect, context)
    return true unless effect.has_conditions?
    
    effect.evaluate_conditions(context)
  end
  
  def calculate_effective_value(effect, state)
    base_value = effect.value
    
    # Apply any context-based modifications
    case effect.effect_type
    when 'attack_percentage'
      # Scale with character level if condition specifies
      if has_level_scaling_condition?(effect)
        level = state[:context]['characterLevel'] || DEFAULT_CHARACTER_LEVEL
        base_value * level
      else
        base_value
      end
    else
      base_value
    end
  end
  
  def has_level_scaling_condition?(effect)
    return false unless effect.has_conditions?
    
    effect.conditions.any? do |condition|
      condition['type'] == 'equipment_count' && condition['value'] == 'character_level'
    end
  end
  
  def convert_to_multiplier(effect, value)
    case effect.effect_type
    when 'attack_multiplier', 'critical_multiplier'
      value
    when 'attack_percentage'
      1.0 + (value / 100.0)
    else
      1.0 + (value / 100.0)
    end
  end
  
  def apply_additive_bonus(state, effect_type, total_value, active_effects)
    case effect_type
    when 'attack_flat'
      state[:flat_bonuses] += total_value
    when 'attack_percentage'
      state[:percentage_bonuses] += total_value
    end
    
    state[:stacking_bonuses].concat(active_effects)
    
    add_breakdown_step(state, {
      step: state[:breakdown].length + 1,
      description: "#{effect_type.humanize} bonuses (additive)",
      operation: 'add',
      value: total_value,
      running_total: calculate_current_total(state)
    })
  end
  
  def apply_unique_effect(state, effect, value, item)
    # Unique effects have special handling based on their nature
    case effect.effect_type
    when 'conditional_damage'
      # Add to conditional effects for separate tracking
      state[:conditional_effects] << create_conditional_effect(effect, value, item)
    when 'weapon_specific'
      # Apply only if weapon type matches
      if weapon_type_matches?(effect, state[:context])
        multiplier = convert_to_multiplier(effect, value)
        state[:multiplicative_bonuses] *= multiplier
        
        add_breakdown_step(state, {
          step: state[:breakdown].length + 1,
          description: "#{effect.name} (#{item[:relic_name]}) - Weapon Specific",
          operation: 'multiply',
          value: multiplier,
          running_total: calculate_current_total(state),
          relic_name: item[:relic_name],
          effect_name: effect.name
        })
      end
    end
  end
  
  def weapon_type_matches?(effect, context)
    return true unless effect.has_conditions?
    
    weapon_condition = effect.conditions.find { |c| c['type'] == 'weapon_type' }
    return true unless weapon_condition
    
    context['weaponType'] == weapon_condition['value']
  end
  
  def create_stacking_bonus(item, base_value, stacked_value)
    {
      effect_id: item[:effect].id.to_s,
      effect_name: item[:effect].name,
      relic_name: item[:relic_name],
      base_value: base_value,
      stacked_value: stacked_value,
      stacking_rule: item[:effect].stacking_rule,
      applied_conditions: get_applied_conditions(item[:effect])
    }
  end
  
  def create_conditional_effect(effect, value, item)
    {
      effect_id: effect.id.to_s,
      effect_name: effect.name,
      relic_name: item[:relic_name],
      condition: effect.conditions.first || {},
      is_active: true,
      value: value,
      description: effect.description
    }
  end
  
  def get_applied_conditions(effect)
    return [] unless effect.has_conditions?
    
    effect.conditions.map { |condition| condition['description'] }.compact
  end
  
  def calculate_current_total(state)
    base = state[:base_attack]
    flat = state[:flat_bonuses]
    percentage = state[:percentage_bonuses]
    multiplicative = state[:multiplicative_bonuses]
    
    (base + flat) * (1.0 + percentage / 100.0) * multiplicative
  end
  
  def add_breakdown_step(state, step)
    state[:breakdown] << step
  end
  
  def generate_result(state)
    final_attack_power = calculate_current_total(state)
    total_multiplier = final_attack_power / state[:base_attack]
    
    {
      total_multiplier: total_multiplier.round(3),
      base_multiplier: 1.0,
      stacking_bonuses: state[:stacking_bonuses],
      conditional_effects: state[:conditional_effects],
      warnings_and_errors: state[:warnings] + state[:errors],
      damage_by_type: calculate_damage_by_type(state, final_attack_power),
      final_attack_power: final_attack_power.round(2),
      breakdown: state[:breakdown]
    }
  end
  
  def calculate_damage_by_type(state, final_attack_power)
    # For now, assume all damage is physical unless specified otherwise
    damage_types = initialize_damage_types
    damage_types['physical'] = final_attack_power
    
    # TODO: Implement damage type-specific calculations based on relic effects
    
    damage_types
  end
  
  def generate_cache_key
    CalculationCache.generate_cache_key(relic_ids, context)
  end
  
  def cache_result(cache_key, result)
    input_data = {
      relic_ids: relic_ids,
      context: context,
      options: options
    }
    
    CalculationCache.store_calculation(
      cache_key,
      input_data,
      result,
      expires_in: 1.hour
    )
  rescue => e
    Rails.logger.warn "Failed to cache calculation result: #{e.message}"
  end
  
  def parse_cached_result(cached_data)
    cached_data.deep_symbolize_keys
  end
end