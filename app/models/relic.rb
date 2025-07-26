class Relic < ApplicationRecord
  has_many :relic_effects, dependent: :destroy
  has_many :build_relics, dependent: :destroy
  has_many :builds, through: :build_relics

  # Validations
  validates :name, presence: true, uniqueness: true, length: { maximum: 255 }
  validates :description, presence: true, length: { maximum: 1000 }
  validates :category, presence: true, inclusion: {
    in: %w[Attack Defense Utility Critical Elemental],
    message: "%{value} is not a valid category"
  }
  validates :rarity, presence: true, inclusion: {
    in: %w[common rare epic legendary],
    message: "%{value} is not a valid rarity"
  }
  validates :quality, presence: true, inclusion: {
    in: %w[Delicate Polished Grand],
    message: "%{value} is not a valid quality"
  }
  validates :obtainment_difficulty, presence: true, numericality: {
    in: 1..10,
    message: "must be between 1 and 10"
  }
  validates :icon_url, format: {
    with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
    message: "must be a valid URL"
  }, allow_blank: true

  # JSON validation for conflicts array
  validate :conflicts_must_be_array_of_strings

  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :by_category, ->(category) { where(category: category) }
  scope :by_rarity, ->(rarity) { where(rarity: rarity) }
  scope :by_quality, ->(quality) { where(quality: quality) }
  scope :by_difficulty, ->(min, max = nil) {
    max ? where(obtainment_difficulty: min..max) : where(obtainment_difficulty: min)
  }
  scope :search, ->(query) {
    where("name ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%")
  }
  scope :excluding_ids, ->(ids) { where.not(id: ids) }

  # Ordered scopes
  scope :by_name, -> { order(:name) }
  scope :by_difficulty, -> { order(:obtainment_difficulty) }
  scope :by_rarity_order, -> {
    order(
      Arel.sql("CASE rarity
                WHEN 'legendary' THEN 4
                WHEN 'epic' THEN 3
                WHEN 'rare' THEN 2
                WHEN 'common' THEN 1
                END DESC")
    )
  }

  # Class methods
  def self.categories
    %w[Attack Defense Utility Critical Elemental]
  end

  def self.rarities
    %w[common rare epic legendary]
  end

  def self.qualities
    %w[Delicate Polished Grand]
  end

  def self.difficulty_range
    1..10
  end

  # Instance methods
  def conflicted_with?(other_relic_ids)
    return false if conflicts.blank?

    other_relic_ids = Array(other_relic_ids).map(&:to_s)
    (conflicts & other_relic_ids).any?
  end

  def has_conflicts?
    conflicts.present? && conflicts.any?
  end

  def rarity_numeric
    case rarity
    when "legendary" then 4
    when "epic" then 3
    when "rare" then 2
    when "common" then 1
    else 0
    end
  end

  def total_effects_count
    relic_effects.active.count
  end

  def attack_effects
    relic_effects.active.where(
      effect_type: %w[attack_multiplier attack_flat attack_percentage weapon_specific conditional_damage]
    )
  end

  def critical_effects
    relic_effects.active.where(
      effect_type: %w[critical_multiplier critical_chance]
    )
  end

  def has_conditions?
    relic_effects.active.joins(:conditions).exists?
  end

  # Serialization methods
  def as_json(options = {})
    super(options.merge(
      include: {
        relic_effects: {
          only: [ :id, :effect_type, :name, :description, :value, :stacking_rule, :conditions, :damage_types, :priority ],
          methods: [ :formatted_value ]
        }
      },
      methods: [ :rarity_numeric, :total_effects_count, :has_conflicts? ]
    ))
  end

  def to_calculation_format
    {
      id: id.to_s,
      name: name,
      description: description,
      category: category,
      rarity: rarity,
      quality: quality,
      effects: relic_effects.active.map(&:to_calculation_format),
      iconUrl: icon_url,
      obtainmentDifficulty: obtainment_difficulty,
      conflicts: conflicts || []
    }
  end

  private

  def conflicts_must_be_array_of_strings
    return if conflicts.blank?

    unless conflicts.is_a?(Array)
      errors.add(:conflicts, "must be an array")
      return
    end

    unless conflicts.all? { |conflict| conflict.is_a?(String) }
      errors.add(:conflicts, "must contain only strings (relic IDs)")
    end
  end
end
