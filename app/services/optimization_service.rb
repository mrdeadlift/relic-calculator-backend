class OptimizationService
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Custom error classes
  class OptimizationError < StandardError
    attr_reader :details, :error_code

    def initialize(message, details: {}, error_code: "OPTIMIZATION_ERROR")
      super(message)
      @details = details
      @error_code = error_code
    end
  end

  # Attributes
  attribute :current_relic_ids, default: -> { [] }
  attribute :combat_style, :string, default: "melee"
  attribute :constraints, default: -> { {} }
  attribute :preferences, default: -> { {} }
  attribute :context, default: -> { {} }

  # Constants
  MAX_SUGGESTIONS = 5
  MAX_COMBINATIONS_TO_EVALUATE = 1000
  OPTIMIZATION_TIMEOUT = 10.seconds
  MIN_IMPROVEMENT_THRESHOLD = 0.05 # 5% minimum improvement

  # Class methods
  def self.suggest_optimizations(current_relic_ids, combat_style: "melee", constraints: {}, preferences: {})
    service = new(
      current_relic_ids: Array(current_relic_ids),
      combat_style: combat_style,
      constraints: constraints,
      preferences: preferences
    )

    service.generate_suggestions
  end

  def self.compare_builds(build_configs, comparison_mode: "simple")
    results = []

    build_configs.each do |config|
      calculation_result = CalculationService.calculate_attack_multiplier(
        config[:relic_ids],
        config[:context] || { combatStyle: config[:combat_style] || "melee" }
      )

      results << {
        build_id: config[:build_id] || SecureRandom.hex(8),
        build_name: config[:name] || "Build #{results.length + 1}",
        attack_multipliers: {
          total: calculation_result[:total_multiplier],
          base: calculation_result[:base_multiplier]
        },
        special_effects: extract_special_effects(config[:relic_ids]),
        total_cost: calculate_total_cost(config[:relic_ids]),
        difficulty_rating: calculate_difficulty_rating(config[:relic_ids]),
        pros: generate_pros(calculation_result, config),
        cons: generate_cons(calculation_result, config),
        details: comparison_mode == "detailed" ? calculation_result : nil
      }
    end

    # Determine winner
    winner = results.max_by { |result| result[:attack_multipliers][:total] }

    {
      comparisons: results,
      winner: {
        build_id: winner[:build_id],
        metric: "total_attack_multiplier",
        value: winner[:attack_multipliers][:total]
      },
      summary: generate_comparison_summary(results)
    }
  end

  # Instance methods
  def generate_suggestions
    validate_inputs!

    # Calculate current build performance
    current_result = calculate_current_performance
    current_multiplier = current_result[:total_multiplier]

    # Generate candidate combinations
    candidates = generate_candidate_combinations

    # Evaluate candidates and find improvements
    suggestions = []
    evaluated_count = 0

    Timeout.timeout(OPTIMIZATION_TIMEOUT) do
      candidates.each do |candidate_relic_ids|
        break if evaluated_count >= MAX_COMBINATIONS_TO_EVALUATE
        break if suggestions.length >= MAX_SUGGESTIONS

        begin
          candidate_result = CalculationService.calculate_attack_multiplier(
            candidate_relic_ids,
            build_calculation_context
          )

          improvement = candidate_result[:total_multiplier] - current_multiplier

          if improvement >= MIN_IMPROVEMENT_THRESHOLD
            suggestion = create_suggestion(
              candidate_relic_ids,
              candidate_result,
              improvement,
              current_result
            )

            suggestions << suggestion
          end

          evaluated_count += 1
        rescue CalculationService::CalculationError => e
          # Skip invalid combinations
          next
        end
      end
    end

    # Sort suggestions by improvement potential
    suggestions.sort_by! { |s| -s[:estimated_improvement] }
    suggestions = suggestions.take(MAX_SUGGESTIONS)

    {
      suggestions: suggestions,
      current_rating: current_multiplier,
      metadata: {
        calculation_time: Time.current,
        total_combinations: candidates.length,
        evaluated_combinations: evaluated_count,
        improvement_threshold: MIN_IMPROVEMENT_THRESHOLD
      }
    }
  rescue Timeout::Error
    raise OptimizationError.new(
      "Optimization timed out after #{OPTIMIZATION_TIMEOUT} seconds",
      error_code: "OPTIMIZATION_TIMEOUT"
    )
  rescue => e
    Rails.logger.error "Optimization failed: #{e.message}"
    raise OptimizationError.new("Optimization failed: #{e.message}")
  end

  private

  def validate_inputs!
    if current_relic_ids.length > Build.max_relics_per_build
      raise OptimizationError.new(
        "Too many relics in current build",
        details: { max_relics: Build.max_relics_per_build },
        error_code: "INVALID_BUILD_SIZE"
      )
    end

    unless Build.combat_styles.include?(combat_style)
      raise OptimizationError.new(
        "Invalid combat style: #{combat_style}",
        details: { valid_styles: Build.combat_styles },
        error_code: "INVALID_COMBAT_STYLE"
      )
    end
  end

  def calculate_current_performance
    return { total_multiplier: 1.0 } if current_relic_ids.empty?

    CalculationService.calculate_attack_multiplier(
      current_relic_ids,
      build_calculation_context
    )
  end

  def build_calculation_context
    base_context = {
      combatStyle: combat_style,
      characterLevel: context["characterLevel"] || 50,
      weaponType: context["weaponType"] || "straight_sword",
      conditions: context["conditions"] || {}
    }

    base_context.merge(context)
  end

  def generate_candidate_combinations
    # Get available relics based on constraints
    available_relics = get_available_relics

    candidates = []

    # Strategy 1: Replace individual relics
    candidates.concat(generate_replacement_candidates(available_relics))

    # Strategy 2: Add relics to incomplete builds
    if current_relic_ids.length < Build.max_relics_per_build
      candidates.concat(generate_addition_candidates(available_relics))
    end

    # Strategy 3: Smart combinations based on synergies
    candidates.concat(generate_synergy_candidates(available_relics))

    # Strategy 4: Meta builds for combat style
    candidates.concat(generate_meta_candidates(available_relics))

    # Remove duplicates and invalid combinations
    candidates.uniq.select { |combo| valid_combination?(combo) }
  end

  def get_available_relics
    query = Relic.active.includes(:relic_effects)

    # Apply difficulty constraints
    if constraints["maxDifficulty"]
      query = query.where("obtainment_difficulty <= ?", constraints["maxDifficulty"])
    end

    # Apply category constraints
    if constraints["allowedCategories"]
      query = query.where(category: constraints["allowedCategories"])
    end

    # Exclude specific relics
    if constraints["excludeRelicIds"]
      query = query.where.not(id: constraints["excludeRelicIds"])
    end

    query.to_a
  end

  def generate_replacement_candidates(available_relics)
    candidates = []

    current_relic_ids.each_with_index do |current_id, index|
      available_relics.each do |replacement|
        next if replacement.id.to_s == current_id
        next if current_relic_ids.include?(replacement.id.to_s) # Already in build

        # Create candidate by replacing one relic
        candidate = current_relic_ids.dup
        candidate[index] = replacement.id.to_s

        candidates << candidate
      end
    end

    candidates
  end

  def generate_addition_candidates(available_relics)
    candidates = []
    max_additions = Build.max_relics_per_build - current_relic_ids.length

    # Single additions
    available_relics.each do |relic|
      next if current_relic_ids.include?(relic.id.to_s)

      candidate = current_relic_ids + [ relic.id.to_s ]
      candidates << candidate
    end

    # Multiple additions for very small builds
    if max_additions > 1 && current_relic_ids.length <= 3
      available_relics.combination(2).each do |relic_pair|
        next if relic_pair.any? { |r| current_relic_ids.include?(r.id.to_s) }

        candidate = current_relic_ids + relic_pair.map { |r| r.id.to_s }
        candidates << candidate if candidate.length <= Build.max_relics_per_build
      end
    end

    candidates
  end

  def generate_synergy_candidates(available_relics)
    candidates = []

    # Find relics with similar effects that stack well
    synergy_groups = group_relics_by_synergy(available_relics)

    synergy_groups.each do |group_type, relics|
      next if relics.length < 2

      # Try combinations of 2-3 synergistic relics
      relics.combination(2).each do |relic_pair|
        candidate = relic_pair.map { |r| r.id.to_s }

        # Fill remaining slots with current relics that don't conflict
        remaining_slots = Build.max_relics_per_build - 2
        compatible_current = current_relic_ids.select do |id|
          !candidate.include?(id) &&
          !has_conflicts_with_candidate?(id, candidate)
        end

        candidate += compatible_current.take(remaining_slots)
        candidates << candidate if candidate.length >= 2
      end
    end

    candidates
  end

  def generate_meta_candidates(available_relics)
    # Generate builds based on popular combinations for the combat style
    meta_combinations = get_meta_combinations_for_combat_style

    meta_combinations.select do |combination|
      # Check if all relics in the combination are available
      combination.all? do |relic_id|
        available_relics.any? { |r| r.id.to_s == relic_id }
      end
    end
  end

  def group_relics_by_synergy(relics)
    groups = {
      "attack_boost" => [],
      "critical_focus" => [],
      "weapon_specific" => [],
      "conditional_damage" => [],
      "elemental_damage" => []
    }

    relics.each do |relic|
      relic.relic_effects.each do |effect|
        case effect.effect_type
        when "attack_multiplier", "attack_percentage", "attack_flat"
          groups["attack_boost"] << relic
        when "critical_multiplier", "critical_chance"
          groups["critical_focus"] << relic
        when "weapon_specific"
          groups["weapon_specific"] << relic
        when "conditional_damage"
          groups["conditional_damage"] << relic
        when "elemental_damage"
          groups["elemental_damage"] << relic
        end
      end
    end

    # Remove duplicates
    groups.each { |key, relics| relics.uniq! }

    groups
  end

  def get_meta_combinations_for_combat_style
    # This would typically come from a database of popular builds
    # For now, return some hardcoded combinations based on combat style

    case combat_style
    when "melee"
      [
        [ "physical-attack-up", "improved-straight-sword", "initial-attack-buff" ],
        [ "improved-critical-hits", "three-weapon-bonus", "physical-attack-up" ]
      ]
    when "ranged"
      [
        [ "physical-attack-up", "improved-critical-hits" ],
        [ "three-weapon-bonus", "initial-attack-buff" ]
      ]
    when "magic"
      [
        [ "improved-critical-hits", "physical-attack-up" ]
      ]
    when "hybrid"
      [
        [ "physical-attack-up", "improved-critical-hits", "three-weapon-bonus" ]
      ]
    else
      []
    end
  end

  def valid_combination?(relic_ids)
    return false if relic_ids.length > Build.max_relics_per_build
    return false if relic_ids.uniq.length != relic_ids.length # No duplicates

    # Check for conflicts
    relics = Relic.where(id: relic_ids)
    conflicts = CalculationService.find_conflicts(relics)

    conflicts.empty?
  end

  def has_conflicts_with_candidate?(relic_id, candidate_ids)
    relic = Relic.find_by(id: relic_id)
    return false unless relic&.has_conflicts?

    (relic.conflicts & candidate_ids).any?
  end

  def create_suggestion(relic_ids, calculation_result, improvement, current_result)
    relics = Relic.where(id: relic_ids).includes(:relic_effects)

    {
      relic_ids: relic_ids,
      relics: relics.map(&:to_calculation_format),
      estimated_improvement: improvement.round(3),
      explanation: generate_explanation(relics, improvement, current_result),
      difficulty_rating: calculate_difficulty_rating(relic_ids),
      pros: generate_suggestion_pros(calculation_result, relics),
      cons: generate_suggestion_cons(calculation_result, relics),
      confidence: calculate_confidence_score(calculation_result, improvement)
    }
  end

  def generate_explanation(relics, improvement, current_result)
    improvement_percent = (improvement * 100).round(1)

    explanation = "This combination provides a #{improvement_percent}% increase in attack power. "

    # Identify key contributing factors
    key_effects = []
    relics.each do |relic|
      high_value_effects = relic.relic_effects.select { |e| e.value > 10 }
      key_effects.concat(high_value_effects.map { |e| "#{e.name} from #{relic.name}" })
    end

    if key_effects.any?
      explanation += "Key improvements come from: #{key_effects.take(3).join(', ')}."
    end

    explanation
  end

  def generate_suggestion_pros(calculation_result, relics)
    pros = []

    if calculation_result[:total_multiplier] > 2.0
      pros << "Excellent damage output (#{(calculation_result[:total_multiplier] * 100).round(0)}% of base)"
    end

    if relics.any? { |r| r.rarity == "legendary" }
      pros << "Includes powerful legendary relics"
    end

    if calculation_result[:conditional_effects].any?
      pros << "Has situational bonuses for extra damage"
    end

    easy_relics = relics.count { |r| r.obtainment_difficulty <= 3 }
    if easy_relics > relics.length / 2
      pros << "Most relics are easy to obtain"
    end

    pros
  end

  def generate_suggestion_cons(calculation_result, relics)
    cons = []

    total_difficulty = relics.sum(&:obtainment_difficulty)
    if total_difficulty > 40
      cons << "High overall difficulty to obtain all relics"
    end

    legendary_count = relics.count { |r| r.rarity == "legendary" }
    if legendary_count > 2
      cons << "Requires multiple rare legendary relics"
    end

    if calculation_result[:conditional_effects].length > 3
      cons << "Complex condition management required"
    end

    if calculation_result[:warnings_and_errors].any?
      cons << "Has calculation warnings or edge cases"
    end

    cons
  end

  def calculate_confidence_score(calculation_result, improvement)
    score = 0.5 # Base confidence

    # Higher confidence for larger improvements
    score += [ improvement * 2, 0.3 ].min

    # Lower confidence for very complex builds
    complexity_penalty = calculation_result[:conditional_effects].length * 0.05
    score -= complexity_penalty

    # Lower confidence if there are warnings
    if calculation_result[:warnings_and_errors].any?
      score -= 0.1
    end

    [ [ score, 0.1 ].max, 1.0 ].min # Clamp between 0.1 and 1.0
  end

  def calculate_difficulty_rating(relic_ids)
    relics = Relic.where(id: relic_ids)
    return 0 if relics.empty?

    total_difficulty = relics.sum(:obtainment_difficulty)
    relic_count = relics.count

    # Average difficulty with some weighting for total count
    average_difficulty = total_difficulty.to_f / relic_count
    count_factor = [ relic_count / 9.0, 1.0 ].min # Normalize by max relics

    (average_difficulty * (0.8 + 0.2 * count_factor)).round(1)
  end

  def calculate_total_cost(relic_ids)
    # This would be based on in-game resource costs
    # For now, use difficulty as a proxy for cost
    calculate_difficulty_rating(relic_ids) * 100
  end

  def self.extract_special_effects(relic_ids)
    relics = Relic.where(id: relic_ids).includes(:relic_effects)

    special_effects = []

    relics.each do |relic|
      relic.relic_effects.each do |effect|
        if effect.effect_type.in?(%w[conditional_damage weapon_specific unique])
          special_effects << "#{effect.name} (#{relic.name})"
        end
      end
    end

    special_effects
  end

  def self.generate_pros(calculation_result, config)
    pros = []

    multiplier = calculation_result[:total_multiplier]
    if multiplier > 2.0
      pros << "High damage output (#{(multiplier * 100).round(0)}%)"
    elsif multiplier > 1.5
      pros << "Good damage increase (#{(multiplier * 100).round(0)}%)"
    end

    if calculation_result[:conditional_effects].any?
      pros << "Has situational bonuses"
    end

    pros
  end

  def self.generate_cons(calculation_result, config)
    cons = []

    if calculation_result[:warnings_and_errors].any?
      cons << "Has warnings or calculation issues"
    end

    if calculation_result[:conditional_effects].length > 2
      cons << "Complex condition management"
    end

    cons
  end

  def self.generate_comparison_summary(results)
    best_multiplier = results.max_by { |r| r[:attack_multipliers][:total] }
    worst_multiplier = results.min_by { |r| r[:attack_multipliers][:total] }

    difference = best_multiplier[:attack_multipliers][:total] - worst_multiplier[:attack_multipliers][:total]
    difference_percent = (difference * 100).round(1)

    "The best build (#{best_multiplier[:build_name]}) outperforms the worst by #{difference_percent}% attack power."
  end
end
