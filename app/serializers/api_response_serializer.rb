class ApiResponseSerializer
  class << self
    # Serialize a successful response
    def success(data, message: 'Success', status: :ok, meta: {})
      {
        success: true,
        message: message,
        data: serialize_data(data),
        meta: build_meta(meta)
      }
    end
    
    # Serialize an error response
    def error(message, status: :bad_request, error_code: nil, details: {})
      {
        success: false,
        message: message,
        error_code: error_code,
        details: serialize_data(details),
        meta: build_meta({})
      }
    end
    
    # Serialize paginated collection
    def paginated_collection(collection, page_info, message: 'Data retrieved successfully')
      {
        success: true,
        message: message,
        data: serialize_data(collection),
        meta: build_meta({ pagination: page_info })
      }
    end
    
    # Serialize validation errors
    def validation_errors(record_or_errors)
      errors = case record_or_errors
               when ActiveRecord::Base, ActiveModel::Model
                 {
                   errors: record_or_errors.errors.full_messages,
                   field_errors: record_or_errors.errors.messages
                 }
               when Hash
                 record_or_errors
               when Array
                 { errors: record_or_errors }
               else
                 { errors: [record_or_errors.to_s] }
               end
      
      {
        success: false,
        message: 'Validation failed',
        error_code: 'VALIDATION_ERROR',
        details: errors,
        meta: build_meta({})
      }
    end
    
    private
    
    def serialize_data(data)
      case data
      when ActiveRecord::Base
        serialize_model(data)
      when ActiveRecord::Relation, Array
        data.map { |item| serialize_data(item) }
      when Hash
        data.deep_transform_keys { |key| key.to_s.camelize(:lower) }
      when NilClass
        nil
      else
        data
      end
    end
    
    def serialize_model(model)
      case model.class.name
      when 'Relic'
        RelicSerializer.new(model).as_json
      when 'Build'
        BuildSerializer.new(model).as_json
      when 'RelicEffect'
        RelicEffectSerializer.new(model).as_json
      else
        model.as_json
      end
    end
    
    def build_meta(additional_meta = {})
      base_meta = {
        timestamp: Time.current.iso8601,
        version: 'v1'
      }
      
      # Add request ID if available (from controller context)
      if defined?(request) && request.respond_to?(:request_id)
        base_meta[:request_id] = request.request_id
      end
      
      base_meta.merge(additional_meta)
    end
  end
end

# Individual model serializers
class RelicSerializer
  def initialize(relic)
    @relic = relic
  end
  
  def as_json(options = {})
    {
      id: @relic.id.to_s,
      name: @relic.name,
      description: @relic.description,
      category: @relic.category,
      rarity: @relic.rarity,
      quality: @relic.quality,
      iconUrl: @relic.icon_url,
      obtainmentDifficulty: @relic.obtainment_difficulty,
      conflicts: @relic.conflicts || [],
      active: @relic.active,
      effects: serialize_effects,
      metadata: {
        createdAt: @relic.created_at&.iso8601,
        updatedAt: @relic.updated_at&.iso8601,
        hasConflicts: @relic.has_conflicts?,
        effectCount: @relic.relic_effects.active.count
      }
    }
  end
  
  private
  
  def serialize_effects
    @relic.relic_effects.active.map do |effect|
      RelicEffectSerializer.new(effect).as_json
    end
  end
end

class RelicEffectSerializer
  def initialize(effect)
    @effect = effect
  end
  
  def as_json(options = {})
    {
      id: @effect.id.to_s,
      name: @effect.name,
      description: @effect.description,
      effectType: @effect.effect_type,
      value: @effect.value,
      stackingRule: @effect.stacking_rule,
      priority: @effect.priority,
      conditions: @effect.conditions || [],
      active: @effect.active,
      metadata: {
        hasConditions: @effect.has_conditions?,
        conditionCount: @effect.conditions&.length || 0
      }
    }
  end
end

class BuildSerializer
  def initialize(build)
    @build = build
  end
  
  def as_json(options = {})
    {
      id: @build.id.to_s,
      name: @build.name,
      description: @build.description,
      combatStyle: @build.combat_style,
      isPublic: @build.is_public,
      shareKey: @build.share_key,
      version: @build.version,
      relics: serialize_build_relics,
      statistics: {
        relicCount: @build.relic_count,
        totalDifficulty: @build.total_difficulty_rating,
        averageDifficulty: @build.average_difficulty_rating,
        rarityDistribution: @build.rarity_distribution,
        categoryDistribution: @build.category_distribution,
        hasConditions: @build.has_conditions?
      },
      metadata: {
        createdAt: @build.created_at&.iso8601,
        updatedAt: @build.updated_at&.iso8601,
        canAddRelic: @build.can_add_relic?,
        shareUrl: @build.generate_share_url
      }
    }
  end
  
  private
  
  def serialize_build_relics
    @build.build_relics.includes(:relic).order(:position).map do |build_relic|
      {
        position: build_relic.position,
        customConditions: build_relic.custom_conditions || {},
        relic: RelicSerializer.new(build_relic.relic).as_json,
        metadata: {
          canMoveUp: build_relic.can_move_up?,
          canMoveDown: build_relic.can_move_down?,
          hasCustomConditions: build_relic.has_custom_conditions?,
          effectiveConditions: build_relic.effective_conditions
        }
      }
    end
  end
end

class CalculationResultSerializer
  def initialize(result)
    @result = result
  end
  
  def as_json(options = {})
    {
      totalMultiplier: @result[:total_multiplier],
      baseMultiplier: @result[:base_multiplier] || 1.0,
      finalAttackPower: @result[:final_attack_power],
      stackingBonuses: serialize_stacking_bonuses,
      conditionalEffects: serialize_conditional_effects,
      breakdown: serialize_breakdown,
      damageByType: @result[:damage_by_type] || {},
      warningsAndErrors: @result[:warnings_and_errors] || [],
      metadata: {
        calculationTime: Time.current.iso8601,
        hasConditionalEffects: @result[:conditional_effects]&.any? || false,
        hasWarnings: @result[:warnings_and_errors]&.any? || false,
        breakdownSteps: @result[:breakdown]&.length || 0
      }
    }
  end
  
  private
  
  def serialize_stacking_bonuses
    (@result[:stacking_bonuses] || []).map do |bonus|
      {
        effectId: bonus[:effect_id],
        effectName: bonus[:effect_name],
        relicName: bonus[:relic_name],
        baseValue: bonus[:base_value],
        stackedValue: bonus[:stacked_value],
        stackingRule: bonus[:stacking_rule],
        appliedConditions: bonus[:applied_conditions] || []
      }
    end
  end
  
  def serialize_conditional_effects
    (@result[:conditional_effects] || []).map do |effect|
      {
        effectId: effect[:effect_id],
        effectName: effect[:effect_name],
        relicName: effect[:relic_name],
        condition: effect[:condition] || {},
        isActive: effect[:is_active],
        value: effect[:value],
        description: effect[:description]
      }
    end
  end
  
  def serialize_breakdown
    (@result[:breakdown] || []).map do |step|
      {
        step: step[:step],
        description: step[:description],
        operation: step[:operation],
        value: step[:value],
        runningTotal: step[:running_total],
        relicName: step[:relic_name],
        effectName: step[:effect_name]
      }
    end
  end
end