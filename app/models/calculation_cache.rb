class CalculationCache < ApplicationRecord
  # Validations
  validates :cache_key, presence: true, uniqueness: true
  validates :input_data, presence: true
  validates :result_data, presence: true
  validates :version, presence: true
  validates :hit_count, numericality: { greater_than_or_equal_to: 0 }
  
  # JSON validations
  validate :input_data_must_be_hash
  validate :result_data_must_be_hash
  
  # Callbacks
  before_validation :set_default_version, if: :new_record?
  before_validation :set_default_expires_at, if: :new_record?
  
  # Scopes
  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at <= ?', Time.current) }
  scope :by_version, ->(version) { where(version: version) }
  scope :recent, -> { order(created_at: :desc) }
  scope :most_hit, -> { order(hit_count: :desc) }
  
  # Class methods
  def self.current_version
    '1.0'
  end
  
  def self.default_expiry_time
    1.hour
  end
  
  def self.max_cache_size
    10_000 # Maximum number of cached calculations
  end
  
  def self.cleanup_expired
    expired.delete_all
  end
  
  def self.cleanup_old_entries
    # Keep only the most recent entries if we're over the limit
    if count > max_cache_size
      oldest_ids = order(created_at: :asc)
        .limit(count - max_cache_size)
        .pluck(:id)
      
      where(id: oldest_ids).delete_all
    end
  end
  
  def self.find_cached_result(cache_key)
    active.find_by(cache_key: cache_key)&.tap(&:increment_hit_count!)
  end
  
  def self.store_calculation(cache_key, input_data, result_data, expires_in: nil)
    expires_at = expires_in ? Time.current + expires_in : nil
    
    # Try to update existing cache entry first
    existing = find_by(cache_key: cache_key)
    
    if existing
      existing.update!(
        input_data: input_data,
        result_data: result_data,
        expires_at: expires_at,
        version: current_version,
        updated_at: Time.current
      )
      existing
    else
      create!(
        cache_key: cache_key,
        input_data: input_data,
        result_data: result_data,
        expires_at: expires_at,
        version: current_version
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to store calculation cache: #{e.message}"
    nil
  end
  
  def self.generate_cache_key(relic_ids, context = {})
    # Create a deterministic cache key from input parameters
    normalized_relic_ids = Array(relic_ids).sort
    context_hash = context.to_h.sort.to_h
    
    key_data = {
      relic_ids: normalized_relic_ids,
      context: context_hash,
      version: current_version
    }
    
    Digest::SHA256.hexdigest(key_data.to_json)
  end
  
  def self.cache_statistics
    {
      total_entries: count,
      active_entries: active.count,
      expired_entries: expired.count,
      total_hits: sum(:hit_count),
      average_hits_per_entry: average(:hit_count)&.round(2) || 0,
      most_popular_entries: most_hit.limit(10).pluck(:cache_key, :hit_count),
      cache_size_mb: estimate_cache_size_mb
    }
  end
  
  def self.estimate_cache_size_mb
    # Rough estimate of cache size in MB
    total_json_size = sum("LENGTH(input_data) + LENGTH(result_data)")
    (total_json_size / 1024.0 / 1024.0).round(2)
  end
  
  # Instance methods
  def expired?
    expires_at.present? && expires_at <= Time.current
  end
  
  def active?
    !expired?
  end
  
  def increment_hit_count!
    increment!(:hit_count)
  end
  
  def extend_expiry(additional_time)
    return false if expires_at.blank?
    
    update(expires_at: expires_at + additional_time)
  end
  
  def refresh_expiry(new_expiry_time = self.class.default_expiry_time)
    update(expires_at: Time.current + new_expiry_time)
  end
  
  def input_complexity_score
    # Calculate a complexity score based on input data
    score = 0
    
    if input_data['relic_ids'].present?
      score += input_data['relic_ids'].length * 2
    end
    
    if input_data['context'].present?
      score += input_data['context'].keys.length
    end
    
    score
  end
  
  def result_size_kb
    (result_data.to_json.bytesize / 1024.0).round(2)
  end
  
  def cache_efficiency
    return 0 if hit_count.zero?
    
    # Simple efficiency metric: hits per KB of stored data
    hit_count / [result_size_kb, 0.1].max
  end
  
  def should_be_purged?
    expired? || (hit_count < 2 && created_at < 1.day.ago)
  end
  
  # Serialization methods
  def as_json(options = {})
    super(options.merge(
      methods: [
        :expired?, :active?, :input_complexity_score, 
        :result_size_kb, :cache_efficiency
      ]
    ))
  end
  
  def to_metrics_format
    {
      cache_key: cache_key,
      hit_count: hit_count,
      created_at: created_at,
      expires_at: expires_at,
      complexity_score: input_complexity_score,
      result_size_kb: result_size_kb,
      efficiency: cache_efficiency,
      version: version
    }
  end
  
  private
  
  def set_default_version
    self.version ||= self.class.current_version
  end
  
  def set_default_expires_at
    self.expires_at ||= Time.current + self.class.default_expiry_time
  end
  
  def input_data_must_be_hash
    return if input_data.blank?
    
    unless input_data.is_a?(Hash)
      errors.add(:input_data, "must be a hash")
    end
  end
  
  def result_data_must_be_hash
    return if result_data.blank?
    
    unless result_data.is_a?(Hash)
      errors.add(:result_data, "must be a hash")
    end
  end
end