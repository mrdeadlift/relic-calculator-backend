class Build < ApplicationRecord
  has_many :build_relics, dependent: :destroy
  has_many :relics, through: :build_relics
  
  # Future user association (when authentication is implemented)
  # belongs_to :user, optional: true
  
  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: 1000 }, allow_blank: true
  validates :combat_style, presence: true, inclusion: {
    in: %w[melee ranged magic hybrid],
    message: "%{value} is not a valid combat style"
  }
  validates :share_key, uniqueness: true, allow_blank: true
  validates :version, numericality: { greater_than: 0 }
  
  # JSON validation for metadata
  validate :metadata_must_be_hash
  
  # Callbacks
  before_create :generate_share_key, if: :is_public?
  before_save :increment_version_if_changed
  
  # Scopes
  scope :public_builds, -> { where(is_public: true) }
  scope :private_builds, -> { where(is_public: false) }
  scope :by_combat_style, ->(style) { where(combat_style: style) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :recent, -> { order(created_at: :desc) }
  scope :popular, -> { 
    # This would need a popularity metric, for now just order by creation date
    order(created_at: :desc) 
  }
  scope :search, ->(query) { 
    where("name ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%") 
  }
  
  # Class methods
  def self.combat_styles
    %w[melee ranged magic hybrid]
  end
  
  def self.find_by_share_key(key)
    find_by(share_key: key)
  end
  
  def self.max_relics_per_build
    9 # Based on game mechanics
  end
  
  # Instance methods
  def relic_count
    build_relics.count
  end
  
  def can_add_relic?
    relic_count < self.class.max_relics_per_build
  end
  
  def has_relic?(relic_id)
    relics.exists?(relic_id)
  end
  
  def add_relic(relic, position: nil, custom_conditions: {})
    return false unless can_add_relic?
    return false if has_relic?(relic.id)
    
    # Check for conflicts
    if has_conflicting_relic?(relic)
      return false
    end
    
    position ||= next_available_position
    
    build_relics.create!(
      relic: relic,
      position: position,
      custom_conditions: custom_conditions
    )
  rescue ActiveRecord::RecordInvalid
    false
  end
  
  def remove_relic(relic_id)
    build_relics.where(relic_id: relic_id).destroy_all
    reorder_positions
  end
  
  def reorder_relics(relic_ids_in_order)
    transaction do
      relic_ids_in_order.each_with_index do |relic_id, index|
        build_relics.find_by(relic_id: relic_id)&.update!(position: index)
      end
    end
  end
  
  def has_conflicting_relic?(new_relic)
    return false unless new_relic.has_conflicts?
    
    current_relic_ids = relics.pluck(:id).map(&:to_s)
    new_relic.conflicted_with?(current_relic_ids)
  end
  
  def conflicting_relics_for(new_relic)
    return [] unless new_relic.has_conflicts?
    
    current_relic_ids = relics.pluck(:id).map(&:to_s)
    conflicting_ids = new_relic.conflicts & current_relic_ids
    
    relics.where(id: conflicting_ids)
  end
  
  def total_difficulty_rating
    relics.sum(:obtainment_difficulty)
  end
  
  def average_difficulty_rating
    return 0 if relic_count.zero?
    
    total_difficulty_rating.to_f / relic_count
  end
  
  def rarity_distribution
    relics.group(:rarity).count
  end
  
  def category_distribution
    relics.group(:category).count
  end
  
  def has_conditions?
    relics.joins(:relic_effects).where.not(relic_effects: { conditions: [] }).exists?
  end
  
  def generate_share_url(base_url: nil)
    return nil unless share_key.present?
    
    base_url ||= "#{Rails.application.routes.default_url_options[:host]}/builds/shared"
    "#{base_url}/#{share_key}"
  end
  
  def clone_for_user(user_id = nil, new_name: nil)
    new_build = dup
    new_build.name = new_name || "Copy of #{name}"
    new_build.user_id = user_id
    new_build.share_key = nil
    new_build.is_public = false
    new_build.version = 1
    
    if new_build.save
      # Copy build_relics
      build_relics.each do |build_relic|
        new_build.build_relics.create!(
          relic: build_relic.relic,
          position: build_relic.position,
          custom_conditions: build_relic.custom_conditions
        )
      end
    end
    
    new_build
  end
  
  # Serialization methods
  def as_json(options = {})
    super(options.merge(
      include: {
        relics: {
          include: :relic_effects
        }
      },
      methods: [
        :relic_count, :total_difficulty_rating, :average_difficulty_rating,
        :rarity_distribution, :category_distribution, :has_conditions?
      ]
    ))
  end
  
  def to_calculation_format
    {
      id: id.to_s,
      name: name,
      description: description,
      relics: relics.map(&:id).map(&:to_s),
      combatStyle: combat_style,
      createdAt: created_at,
      updatedAt: updated_at,
      shareKey: share_key,
      isPublic: is_public
    }
  end
  
  def to_share_format
    {
      name: name,
      description: description,
      combat_style: combat_style,
      relics: build_relics.includes(:relic).order(:position).map do |build_relic|
        {
          relic_id: build_relic.relic.id,
          position: build_relic.position,
          custom_conditions: build_relic.custom_conditions,
          relic: build_relic.relic.to_calculation_format
        }
      end,
      metadata: {
        total_difficulty: total_difficulty_rating,
        relic_count: relic_count,
        created_at: created_at,
        version: version
      }
    }
  end
  
  private
  
  def generate_share_key
    loop do
      self.share_key = SecureRandom.urlsafe_base64(12)
      break unless self.class.exists?(share_key: share_key)
    end
  end
  
  def increment_version_if_changed
    if persisted? && (name_changed? || description_changed? || combat_style_changed?)
      self.version += 1
    end
  end
  
  def next_available_position
    max_position = build_relics.maximum(:position) || -1
    max_position + 1
  end
  
  def reorder_positions
    build_relics.order(:position).each_with_index do |build_relic, index|
      build_relic.update_column(:position, index)
    end
  end
  
  def metadata_must_be_hash
    return if metadata.blank?
    
    unless metadata.is_a?(Hash)
      errors.add(:metadata, "must be a hash")
    end
  end
end