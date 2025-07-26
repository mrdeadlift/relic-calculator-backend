class RelicValidationService
  include ActiveModel::Model
  include ActiveModel::Attributes
  
  # Custom error classes
  class ValidationError < StandardError
    attr_reader :details, :error_code
    
    def initialize(message, details: {}, error_code: 'VALIDATION_ERROR')
      super(message)
      @details = details
      @error_code = error_code
    end
  end
  
  class RelicNotFoundError < ValidationError
    def initialize(message = 'Relic not found')
      super(message, error_code: 'RELIC_NOT_FOUND')
    end
  end
  
  class ConflictDetectedError < ValidationError
    def initialize(message = 'Conflicting relics detected')
      super(message, error_code: 'CONFLICTING_RELICS')
    end
  end
  
  # Attributes
  attribute :relic_ids, default: -> { [] }
  attribute :context, default: -> { {} }
  attribute :strict_mode, :boolean, default: false
  
  # Constants
  MAX_RELICS_PER_BUILD = 9
  REQUIRED_RELIC_FIELDS = %w[id name category rarity quality].freeze
  VALID_CATEGORIES = %w[weapon armor accessory consumable special].freeze
  VALID_RARITIES = %w[common uncommon rare epic legendary mythic].freeze
  VALID_QUALITIES = %w[normal enhanced superior masterwork].freeze
  
  # Class methods
  def self.validate_relic_combination(relic_ids, context: {}, strict_mode: false)
    service = new(
      relic_ids: Array(relic_ids),
      context: context,
      strict_mode: strict_mode
    )
    
    service.validate
  end
  
  def self.preprocess_relics_for_calculation(relic_ids, context: {})
    service = new(relic_ids: Array(relic_ids), context: context)
    relics = service.validate
    
    service.preprocess_relics(relics)
  end
  
  def self.validate_single_relic(relic)
    service = new
    service.validate_relic_structure(relic)
  end
  
  # Instance methods
  def validate
    validate_input_parameters!
    
    # Load relics from database
    relics = load_and_verify_relics
    
    # Validate relic structures
    validate_relic_structures(relics) if strict_mode
    
    # Check for conflicts
    validate_no_conflicts(relics)
    
    # Validate effects
    validate_relic_effects(relics)
    
    # Context-specific validations
    validate_context_compatibility(relics) if context.present?
    
    relics
  end
  
  def preprocess_relics(relics)
    processed_relics = relics.map do |relic|
      {
        id: relic.id.to_s,
        name: relic.name,
        category: relic.category,
        rarity: relic.rarity,
        quality: relic.quality,
        effects: preprocess_relic_effects(relic.relic_effects),
        conflicts: relic.conflicts || [],
        metadata: extract_relic_metadata(relic)
      }
    end
    
    {
      relics: processed_relics,
      summary: generate_combination_summary(relics),
      warnings: generate_warnings(relics),
      preprocessing_metadata: {
        total_relics: relics.length,
        processed_at: Time.current,
        context_applied: context.present?
      }
    }
  end
  
  def validate_relic_structure(relic)
    errors = []
    
    # Check required fields
    REQUIRED_RELIC_FIELDS.each do |field|
      if relic.send(field).blank?
        errors << "Missing required field: #{field}"
      end
    end
    
    # Validate category
    unless VALID_CATEGORIES.include?(relic.category)
      errors << "Invalid category: #{relic.category}. Must be one of: #{VALID_CATEGORIES.join(', ')}"
    end
    
    # Validate rarity
    unless VALID_RARITIES.include?(relic.rarity)
      errors << "Invalid rarity: #{relic.rarity}. Must be one of: #{VALID_RARITIES.join(', ')}"
    end
    
    # Validate quality
    unless VALID_QUALITIES.include?(relic.quality)
      errors << "Invalid quality: #{relic.quality}. Must be one of: #{VALID_QUALITIES.join(', ')}"
    end
    
    # Validate obtainment difficulty
    if relic.obtainment_difficulty.present? && (relic.obtainment_difficulty < 1 || relic.obtainment_difficulty > 10)
      errors << "Obtainment difficulty must be between 1 and 10"
    end
    
    if errors.any?
      raise ValidationError.new(
        "Relic validation failed for #{relic.name}",
        details: { errors: errors, relic_id: relic.id },
        error_code: 'INVALID_RELIC_STRUCTURE'
      )
    end
    
    true
  end
  
  private
  
  def validate_input_parameters!
    if relic_ids.empty?
      raise ValidationError.new(
        "No relics provided for validation",
        error_code: 'EMPTY_RELIC_LIST'
      )
    end
    
    if relic_ids.length > MAX_RELICS_PER_BUILD
      raise ValidationError.new(
        "Too many relics provided (max: #{MAX_RELICS_PER_BUILD})",
        details: { max_relics: MAX_RELICS_PER_BUILD, provided_count: relic_ids.length },
        error_code: 'RELIC_LIMIT_EXCEEDED'
      )
    end
    
    # Check for duplicates
    if relic_ids.uniq.length != relic_ids.length
      duplicates = relic_ids.group_by(&:itself).select { |_, v| v.length > 1 }.keys
      raise ValidationError.new(
        "Duplicate relics detected",
        details: { duplicate_ids: duplicates },
        error_code: 'DUPLICATE_RELICS'
      )
    end
  end
  
  def load_and_verify_relics
    relics = Relic.where(id: relic_ids).includes(:relic_effects)
    
    if relics.count != relic_ids.length
      found_ids = relics.pluck(:id).map(&:to_s)
      missing_ids = relic_ids - found_ids
      
      raise RelicNotFoundError.new(
        "Relics not found: #{missing_ids.join(', ')}",
        details: { missing_relic_ids: missing_ids },
        error_code: 'RELIC_NOT_FOUND'
      )
    end
    
    # Check if relics are active
    inactive_relics = relics.select { |r| !r.active? }
    if inactive_relics.any?
      raise ValidationError.new(
        "Inactive relics detected",
        details: { inactive_relic_ids: inactive_relics.map(&:id).map(&:to_s) },
        error_code: 'INACTIVE_RELICS'
      )
    end
    
    relics
  end
  
  def validate_relic_structures(relics)
    relics.each do |relic|
      validate_relic_structure(relic)
    end
  end
  
  def validate_no_conflicts(relics)
    conflicts = CalculationService.find_conflicts(relics)
    
    if conflicts.any?
      raise ConflictDetectedError.new(
        "Conflicting relics detected in combination",
        details: { conflicts: conflicts },
        error_code: 'CONFLICTING_RELICS'
      )
    end
  end
  
  def validate_relic_effects(relics)
    relics.each do |relic|
      relic.relic_effects.each do |effect|
        validate_effect_structure(effect, relic)
      end
    end
  end
  
  def validate_effect_structure(effect, relic)
    errors = []
    
    # Check required effect fields
    if effect.name.blank?
      errors << "Effect missing name"
    end
    
    if effect.effect_type.blank?
      errors << "Effect missing type"
    end
    
    if effect.value.blank? || !effect.value.is_a?(Numeric)
      errors << "Effect missing or invalid value"
    end
    
    # Validate stacking rule
    valid_stacking_rules = %w[additive multiplicative overwrite unique]
    unless valid_stacking_rules.include?(effect.stacking_rule)
      errors << "Invalid stacking rule: #{effect.stacking_rule}"
    end
    
    # Validate conditions format if present
    if effect.conditions.present?
      validate_effect_conditions(effect.conditions, errors)
    end
    
    if errors.any?
      raise ValidationError.new(
        "Invalid effect structure in relic #{relic.name}",
        details: { 
          errors: errors, 
          relic_id: relic.id, 
          effect_id: effect.id 
        },
        error_code: 'INVALID_EFFECT_STRUCTURE'
      )
    end
  end
  
  def validate_effect_conditions(conditions, errors)
    conditions.each_with_index do |condition, index|
      unless condition.is_a?(Hash)
        errors << "Condition #{index + 1} must be a hash"
        next
      end
      
      unless condition['type'].present?
        errors << "Condition #{index + 1} missing type"
      end
      
      unless condition['value'].present?
        errors << "Condition #{index + 1} missing value"
      end
    end
  end
  
  def validate_context_compatibility(relics)
    # Validate that relics are compatible with the given context
    if context['combatStyle'].present?
      incompatible_relics = find_combat_style_incompatible_relics(relics, context['combatStyle'])
      
      if incompatible_relics.any? && strict_mode
        raise ValidationError.new(
          "Relics incompatible with combat style #{context['combatStyle']}",
          details: { 
            incompatible_relics: incompatible_relics.map(&:name),
            combat_style: context['combatStyle']
          },
          error_code: 'COMBAT_STYLE_INCOMPATIBLE'
        )
      end
    end
    
    if context['weaponType'].present?
      incompatible_relics = find_weapon_type_incompatible_relics(relics, context['weaponType'])
      
      if incompatible_relics.any? && strict_mode
        raise ValidationError.new(
          "Relics incompatible with weapon type #{context['weaponType']}",
          details: { 
            incompatible_relics: incompatible_relics.map(&:name),
            weapon_type: context['weaponType']
          },
          error_code: 'WEAPON_TYPE_INCOMPATIBLE'
        )
      end
    end
  end
  
  def find_combat_style_incompatible_relics(relics, combat_style)
    relics.select do |relic|
      relic.relic_effects.any? do |effect|
        effect.conditions.present? && 
        effect.conditions.any? { |c| c['type'] == 'combat_style' && c['value'] != combat_style }
      end
    end
  end
  
  def find_weapon_type_incompatible_relics(relics, weapon_type)
    relics.select do |relic|
      relic.relic_effects.any? do |effect|
        effect.conditions.present? && 
        effect.conditions.any? { |c| c['type'] == 'weapon_type' && c['value'] != weapon_type }
      end
    end
  end
  
  def preprocess_relic_effects(relic_effects)
    relic_effects.active.map do |effect|
      {
        id: effect.id.to_s,
        name: effect.name,
        description: effect.description,
        effect_type: effect.effect_type,
        value: effect.value,
        stacking_rule: effect.stacking_rule,
        priority: effect.priority,
        conditions: effect.conditions || [],
        active: effect.active,
        metadata: {
          created_at: effect.created_at,
          updated_at: effect.updated_at,
          has_conditions: effect.has_conditions?
        }
      }
    end
  end
  
  def extract_relic_metadata(relic)
    {
      obtainment_difficulty: relic.obtainment_difficulty,
      icon_url: relic.icon_url,
      effect_count: relic.relic_effects.active.count,
      has_conflicts: relic.has_conflicts?,
      conflict_count: relic.conflicts&.length || 0,
      created_at: relic.created_at,
      updated_at: relic.updated_at
    }
  end
  
  def generate_combination_summary(relics)
    {
      total_relics: relics.length,
      categories: relics.group_by(&:category).transform_values(&:count),
      rarities: relics.group_by(&:rarity).transform_values(&:count),
      qualities: relics.group_by(&:quality).transform_values(&:count),
      total_effects: relics.sum { |r| r.relic_effects.active.count },
      total_difficulty: relics.sum(&:obtainment_difficulty),
      average_difficulty: relics.sum(&:obtainment_difficulty).to_f / relics.length,
      has_conflicts: relics.any?(&:has_conflicts?)
    }
  end
  
  def generate_warnings(relics)
    warnings = []
    
    # High difficulty warning
    total_difficulty = relics.sum(&:obtainment_difficulty)
    if total_difficulty > 40
      warnings << {
        type: 'high_difficulty',
        message: 'This combination has very high obtainment difficulty',
        details: { total_difficulty: total_difficulty }
      }
    end
    
    # Too many legendary relics warning
    legendary_count = relics.count { |r| r.rarity == 'legendary' }
    if legendary_count > 3
      warnings << {
        type: 'many_legendaries',
        message: 'This combination requires many legendary relics',
        details: { legendary_count: legendary_count }
      }
    end
    
    # Complex conditions warning
    complex_effects_count = relics.sum do |relic|
      relic.relic_effects.count { |effect| effect.conditions.present? && effect.conditions.length > 2 }
    end
    
    if complex_effects_count > 5
      warnings << {
        type: 'complex_conditions',
        message: 'This combination has many complex conditional effects',
        details: { complex_effects_count: complex_effects_count }
      }
    end
    
    warnings
  end
end