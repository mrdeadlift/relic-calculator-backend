class RelicEffect < ApplicationRecord
  belongs_to :relic
  
  # Validations
  validates :effect_type, presence: true, inclusion: {
    in: %w[
      attack_multiplier attack_flat attack_percentage 
      critical_multiplier critical_chance 
      elemental_damage conditional_damage 
      weapon_specific unique
    ],
    message: "%{value} is not a valid effect type"
  }
  validates :name, presence: true, length: { maximum: 255 }
  validates :description, presence: true, length: { maximum: 500 }
  validates :value, presence: true, numericality: { 
    greater_than: 0,
    less_than_or_equal_to: 1000,
    message: "must be a positive number not exceeding 1000"
  }
  validates :stacking_rule, presence: true, inclusion: {
    in: %w[additive multiplicative overwrite unique],
    message: "%{value} is not a valid stacking rule"
  }
  validates :priority, numericality: { 
    in: 0..10,
    message: "must be between 0 and 10"
  }
  
  # JSON validations
  validate :conditions_must_be_valid_array
  validate :damage_types_must_be_valid_array
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :by_type, ->(type) { where(effect_type: type) }
  scope :by_stacking_rule, ->(rule) { where(stacking_rule: rule) }
  scope :with_conditions, -> { where.not(conditions: []) }
  scope :without_conditions, -> { where(conditions: []) }
  scope :by_damage_type, ->(damage_type) { 
    where("JSON_CONTAINS(damage_types, ?)", [damage_type].to_json) 
  }
  scope :by_priority, -> { order(:priority) }
  scope :by_priority_desc, -> { order(priority: :desc) }
  
  # Class methods
  def self.effect_types
    %w[
      attack_multiplier attack_flat attack_percentage 
      critical_multiplier critical_chance 
      elemental_damage conditional_damage 
      weapon_specific unique
    ]
  end
  
  def self.stacking_rules
    %w[additive multiplicative overwrite unique]
  end
  
  def self.damage_types
    %w[physical magical fire ice lightning dark holy]
  end
  
  # Instance methods
  def has_conditions?
    conditions.present? && conditions.any?
  end
  
  def applies_to_damage_type?(damage_type)
    damage_types.include?(damage_type.to_s)
  end
  
  def is_conditional?
    effect_type == 'conditional_damage' || has_conditions?
  end
  
  def is_percentage_based?
    %w[attack_percentage critical_chance].include?(effect_type)
  end
  
  def is_multiplier_based?
    %w[attack_multiplier critical_multiplier].include?(effect_type)
  end
  
  def is_flat_bonus?
    effect_type == 'attack_flat'
  end
  
  def formatted_value
    case effect_type
    when 'attack_percentage', 'critical_chance'
      "#{value}%"
    when 'attack_multiplier', 'critical_multiplier'
      "×#{value}"
    when 'attack_flat'
      "+#{value.to_i}"
    else
      value.to_s
    end
  end
  
  def condition_descriptions
    return [] unless has_conditions?
    
    conditions.map { |condition| condition['description'] }.compact
  end
  
  def evaluate_conditions(context = {})
    return true unless has_conditions?
    
    conditions.all? do |condition|
      evaluate_single_condition(condition, context)
    end
  end
  
  # Calculation helper methods
  def calculate_effect_value(base_value, context = {})
    return 0 unless evaluate_conditions(context)
    
    case stacking_rule
    when 'additive'
      value
    when 'multiplicative' 
      is_percentage_based? ? (base_value * value / 100) : (base_value * value)
    when 'overwrite'
      value
    when 'unique'
      value
    else
      value
    end
  end
  
  # Serialization methods
  def as_json(options = {})
    super(options.merge(
      methods: [:formatted_value, :has_conditions?, :is_conditional?, :condition_descriptions]
    ))
  end
  
  def to_calculation_format
    {
      id: id.to_s,
      type: effect_type,
      value: value,
      stackingRule: stacking_rule,
      conditions: conditions || [],
      damageTypes: damage_types || [],
      name: name,
      description: description
    }
  end
  
  private
  
  def conditions_must_be_valid_array
    return if conditions.blank?
    
    unless conditions.is_a?(Array)
      errors.add(:conditions, "must be an array")
      return
    end
    
    conditions.each_with_index do |condition, index|
      unless condition.is_a?(Hash)
        errors.add(:conditions, "condition #{index + 1} must be a hash")
        next
      end
      
      required_keys = %w[id type value description]
      missing_keys = required_keys - condition.keys
      
      if missing_keys.any?
        errors.add(:conditions, "condition #{index + 1} missing keys: #{missing_keys.join(', ')}")
      end
      
      # Validate condition type
      valid_condition_types = %w[
        weapon_type combat_style health_threshold 
        chain_position enemy_type time_based equipment_count
      ]
      
      unless valid_condition_types.include?(condition['type'])
        errors.add(:conditions, "condition #{index + 1} has invalid type: #{condition['type']}")
      end
    end
  end
  
  def damage_types_must_be_valid_array
    return if damage_types.blank?
    
    unless damage_types.is_a?(Array)
      errors.add(:damage_types, "must be an array")
      return
    end
    
    valid_damage_types = self.class.damage_types
    invalid_types = damage_types - valid_damage_types
    
    if invalid_types.any?
      errors.add(:damage_types, "contains invalid types: #{invalid_types.join(', ')}")
    end
  end
  
  def evaluate_single_condition(condition, context)
    condition_type = condition['type']
    condition_value = condition['value']
    
    case condition_type
    when 'weapon_type'
      context[:weapon_type] == condition_value
    when 'combat_style'
      context[:combat_style] == condition_value
    when 'health_threshold'
      context[:health_percentage] && context[:health_percentage] <= condition_value.to_f
    when 'chain_position'
      context[:chain_position] == condition_value.to_i
    when 'enemy_type'
      context[:enemy_type] == condition_value
    when 'time_based'
      # Time-based conditions would need specific implementation
      true
    when 'equipment_count'
      context[:equipment_count] && context[:equipment_count] >= condition_value.to_i
    else
      # Unknown condition type defaults to false for safety
      false
    end
  end
end