class BuildRelic < ApplicationRecord
  belongs_to :build
  belongs_to :relic
  
  # Validations
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :build_id, uniqueness: { scope: :relic_id, message: "already contains this relic" }
  validates :build_id, uniqueness: { scope: :position, message: "position already taken" }
  
  # JSON validation for custom_conditions
  validate :custom_conditions_must_be_hash
  
  # Callbacks
  before_validation :set_default_position, if: :new_record?
  after_destroy :reorder_sibling_positions
  
  # Scopes
  scope :ordered, -> { order(:position) }
  scope :by_position, ->(pos) { where(position: pos) }
  scope :in_build, ->(build_id) { where(build_id: build_id) }
  
  # Instance methods
  def move_to_position(new_position)
    return false if new_position < 0
    return true if position == new_position
    
    transaction do
      # Temporarily set to a very high position to avoid conflicts
      update_column(:position, 9999)
      
      # Shift other positions
      if new_position < position
        # Moving up: shift others down
        build.build_relics.where(position: new_position...position).
          update_all("position = position + 1")
      else
        # Moving down: shift others up
        build.build_relics.where(position: (position + 1)..new_position).
          update_all("position = position - 1")
      end
      
      # Set the final position
      update_column(:position, new_position)
    end
    
    true
  rescue => e
    Rails.logger.error "Failed to move BuildRelic to position #{new_position}: #{e.message}"
    false
  end
  
  def next_position
    build.build_relics.where("position > ?", position).minimum(:position)
  end
  
  def previous_position
    build.build_relics.where("position < ?", position).maximum(:position)
  end
  
  def can_move_up?
    previous_position.present?
  end
  
  def can_move_down?
    next_position.present?
  end
  
  def move_up
    return false unless can_move_up?
    
    target_position = previous_position
    other_build_relic = build.build_relics.find_by(position: target_position)
    
    transaction do
      other_build_relic.update_column(:position, position)
      update_column(:position, target_position)
    end
    
    true
  rescue
    false
  end
  
  def move_down
    return false unless can_move_down?
    
    target_position = next_position
    other_build_relic = build.build_relics.find_by(position: target_position)
    
    transaction do
      other_build_relic.update_column(:position, position)
      update_column(:position, target_position)
    end
    
    true
  rescue
    false
  end
  
  def has_custom_conditions?
    custom_conditions.present? && custom_conditions.any?
  end
  
  def effective_conditions
    base_conditions = relic.relic_effects.flat_map { |effect| effect.conditions || [] }
    
    return base_conditions unless has_custom_conditions?
    
    # Merge custom conditions with base conditions
    # Custom conditions override base conditions with the same ID
    merged_conditions = base_conditions.dup
    
    custom_conditions.each do |custom_condition|
      existing_index = merged_conditions.find_index { |c| c['id'] == custom_condition['id'] }
      
      if existing_index
        merged_conditions[existing_index] = custom_condition
      else
        merged_conditions << custom_condition
      end
    end
    
    merged_conditions
  end
  
  def condition_overrides
    return {} unless has_custom_conditions?
    
    overrides = {}
    custom_conditions.each do |condition|
      overrides[condition['id']] = condition['value']
    end
    
    overrides
  end
  
  def set_custom_condition(condition_id, value, description: nil)
    self.custom_conditions ||= []
    
    existing_condition = custom_conditions.find { |c| c['id'] == condition_id }
    
    if existing_condition
      existing_condition['value'] = value
      existing_condition['description'] = description if description.present?
    else
      new_condition = {
        'id' => condition_id,
        'value' => value,
        'type' => 'custom_override'
      }
      new_condition['description'] = description if description.present?
      
      custom_conditions << new_condition
    end
    
    save
  end
  
  def remove_custom_condition(condition_id)
    return false unless has_custom_conditions?
    
    custom_conditions.reject! { |c| c['id'] == condition_id }
    save
  end
  
  def clear_custom_conditions
    self.custom_conditions = {}
    save
  end
  
  # Serialization methods
  def as_json(options = {})
    super(options.merge(
      include: {
        relic: {
          include: :relic_effects
        }
      },
      methods: [
        :has_custom_conditions?, :can_move_up?, :can_move_down?,
        :effective_conditions, :condition_overrides
      ]
    ))
  end
  
  def to_calculation_format
    {
      relicId: relic.id.to_s,
      position: position,
      customConditions: custom_conditions || {},
      relic: relic.to_calculation_format
    }
  end
  
  private
  
  def set_default_position
    return if position.present?
    
    max_position = build&.build_relics&.maximum(:position) || -1
    self.position = max_position + 1
  end
  
  def reorder_sibling_positions
    return unless build.present?
    
    # Reorder positions to fill gaps
    build.build_relics.order(:position).each_with_index do |build_relic, index|
      build_relic.update_column(:position, index) if build_relic.position != index
    end
  end
  
  def custom_conditions_must_be_hash
    return if custom_conditions.blank?
    
    unless custom_conditions.is_a?(Hash) || custom_conditions.is_a?(Array)
      errors.add(:custom_conditions, "must be a hash or array")
      return
    end
    
    # If it's an array, validate each condition
    if custom_conditions.is_a?(Array)
      custom_conditions.each_with_index do |condition, index|
        unless condition.is_a?(Hash)
          errors.add(:custom_conditions, "condition #{index + 1} must be a hash")
          next
        end
        
        required_keys = %w[id value]
        missing_keys = required_keys - condition.keys
        
        if missing_keys.any?
          errors.add(:custom_conditions, "condition #{index + 1} missing keys: #{missing_keys.join(', ')}")
        end
      end
    end
  end
end