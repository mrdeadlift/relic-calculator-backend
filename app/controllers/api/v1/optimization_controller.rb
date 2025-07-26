class Api::V1::OptimizationController < Api::V1::BaseController
  # POST /api/v1/optimization/suggest
  def suggest
    current_relic_ids = parse_relic_ids
    context = parse_context_params
    constraints = parse_optimization_constraints
    preferences = parse_optimization_preferences

    # Validate inputs
    return unless validate_required_params!(:relic_ids)
    return unless validate_relic_ids!(current_relic_ids)

    combat_style = context["combatStyle"] || params[:combat_style] || "melee"
    return unless validate_combat_style!(combat_style)

    # Validate current combination
    RelicValidationService.validate_relic_combination(
      current_relic_ids,
      context: context
    )

    # Generate optimization suggestions
    optimization_result = OptimizationService.suggest_optimizations(
      current_relic_ids,
      combat_style: combat_style,
      constraints: constraints,
      preferences: preferences
    )

    render_success(
      optimization_result,
      message: "Optimization suggestions generated successfully",
      meta: {
        current_build: {
          relic_count: current_relic_ids.length,
          combat_style: combat_style
        },
        constraints: constraints,
        preferences: preferences,
        suggestion_count: optimization_result[:suggestions]&.length || 0
      }
    )
  end

  # POST /api/v1/optimization/analyze
  def analyze
    relic_ids = parse_relic_ids
    context = parse_context_params

    return unless validate_required_params!(:relic_ids)
    return unless validate_relic_ids!(relic_ids)

    # Validate and preprocess relics
    preprocessed_result = RelicValidationService.preprocess_relics_for_calculation(
      relic_ids,
      context: context
    )

    # Calculate current performance
    calculation_result = CalculationService.calculate_attack_multiplier(
      relic_ids,
      context,
      { include_breakdown: true }
    )

    # Generate analysis insights
    analysis_result = generate_build_analysis(
      preprocessed_result,
      calculation_result,
      context
    )

    render_success(
      analysis_result,
      message: "Build analysis completed successfully",
      meta: {
        relic_count: relic_ids.length,
        context: context,
        performance_rating: analysis_result[:performance_rating]
      }
    )
  end

  # POST /api/v1/optimization/meta_builds
  def meta_builds
    combat_style = params[:combat_style] || params[:combatStyle] || "melee"
    return unless validate_combat_style!(combat_style)

    context = parse_context_params
    constraints = parse_optimization_constraints

    # Generate meta build suggestions
    meta_builds = generate_meta_builds_for_style(combat_style, constraints, context)

    render_success(
      meta_builds,
      message: "Meta builds retrieved successfully",
      meta: {
        combat_style: combat_style,
        build_count: meta_builds.length,
        constraints: constraints
      }
    )
  end

  # GET /api/v1/optimization/cache_stats
  def cache_statistics
    stats = CalculationCache.cache_statistics

    render_success(
      stats,
      message: "Cache statistics retrieved successfully"
    )
  end

  # DELETE /api/v1/optimization/cache
  def clear_cache
    # Only allow in development or with admin privileges
    unless Rails.env.development? || params[:admin_key] == Rails.application.secret_key_base
      render_error(
        "Unauthorized to clear cache",
        status: :unauthorized,
        error_code: "UNAUTHORIZED"
      )
      return
    end

    cleared_count = CalculationCache.count
    CalculationCache.delete_all

    render_success(
      { cleared_entries: cleared_count },
      message: "Cache cleared successfully"
    )
  end

  # POST /api/v1/optimization/compare
  def compare
    combinations = parse_comparison_combinations

    if combinations.empty?
      render_error(
        "At least two combinations are required for comparison",
        status: :bad_request,
        error_code: "INSUFFICIENT_COMBINATIONS"
      )
      return
    end

    if combinations.length > 10
      render_error(
        "Too many combinations for comparison (max: 10)",
        status: :bad_request,
        error_code: "TOO_MANY_COMBINATIONS",
        details: { max_combinations: 10, provided_count: combinations.length }
      )
      return
    end

    # Calculate performance for each combination
    comparison_results = []
    errors = []

    combinations.each_with_index do |combination, index|
      begin
        # Validate combination
        RelicValidationService.validate_relic_combination(
          combination[:relic_ids],
          context: combination[:context]
        )

        # Calculate performance
        calculation_result = CalculationService.calculate_attack_multiplier(
          combination[:relic_ids],
          combination[:context],
          { include_breakdown: params[:include_breakdown] != "false" }
        )

        # Generate analysis
        analysis = generate_comparison_analysis(
          combination,
          calculation_result,
          index
        )

        comparison_results << {
          combination_id: combination[:id] || "combination_#{index}",
          name: combination[:name] || "Build #{index + 1}",
          performance: calculation_result,
          analysis: analysis,
          metadata: {
            relic_count: combination[:relic_ids].length,
            combat_style: combination[:context]["combatStyle"] || "melee"
          }
        }
      rescue => e
        errors << {
          combination_id: combination[:id] || "combination_#{index}",
          error: e.message,
          error_code: e.respond_to?(:error_code) ? e.error_code : "CALCULATION_ERROR"
        }
      end
    end

    # Determine winner and rankings
    if comparison_results.any?
      winner_analysis = determine_comparison_winner(comparison_results)
      rankings = generate_performance_rankings(comparison_results)

      render_success(
        {
          comparisons: comparison_results,
          winner: winner_analysis,
          rankings: rankings,
          summary: generate_comparison_summary(comparison_results),
          errors: errors
        },
        message: "Build comparison completed successfully",
        meta: {
          total_combinations: combinations.length,
          successful_comparisons: comparison_results.length,
          failed_comparisons: errors.length,
          comparison_mode: params[:comparison_mode] || "simple"
        }
      )
    else
      render_error(
        "All combinations failed to calculate",
        status: :bad_request,
        error_code: "ALL_CALCULATIONS_FAILED",
        details: { errors: errors }
      )
    end
  end

  # POST /api/v1/optimization/batch_calculate
  def batch_calculate
    combinations = parse_batch_combinations

    if combinations.empty?
      render_error(
        "At least one combination is required",
        status: :bad_request,
        error_code: "EMPTY_COMBINATIONS_LIST"
      )
      return
    end

    if combinations.length > 50
      render_error(
        "Too many combinations for batch calculation (max: 50)",
        status: :bad_request,
        error_code: "TOO_MANY_COMBINATIONS",
        details: { max_combinations: 50, provided_count: combinations.length }
      )
      return
    end

    # Process combinations in parallel
    results = []
    errors = []

    combinations.each_with_index do |combination, index|
      begin
        # Validate combination
        RelicValidationService.validate_relic_combination(
          combination[:relic_ids],
          context: combination[:context]
        )

        # Calculate
        calculation_result = CalculationService.calculate_attack_multiplier(
          combination[:relic_ids],
          combination[:context]
        )

        results << {
          index: index,
          combination_id: combination[:id],
          result: calculation_result,
          success: true
        }
      rescue => e
        errors << {
          index: index,
          combination_id: combination[:id],
          error: e.message,
          error_code: e.respond_to?(:error_code) ? e.error_code : "CALCULATION_ERROR",
          success: false
        }
      end
    end

    render_success(
      {
        results: results,
        errors: errors,
        summary: {
          total_combinations: combinations.length,
          successful_calculations: results.length,
          failed_calculations: errors.length,
          success_rate: (results.length.to_f / combinations.length * 100).round(2)
        }
      },
      message: "Batch calculation completed",
      status: errors.any? ? :partial_content : :ok
    )
  end

  private

  def generate_build_analysis(preprocessed_result, calculation_result, context)
    relics = preprocessed_result[:relics]
    summary = preprocessed_result[:summary]
    warnings = preprocessed_result[:warnings]

    # Calculate performance metrics
    total_multiplier = calculation_result[:total_multiplier]
    performance_rating = calculate_performance_rating(total_multiplier, summary)

    # Analyze synergies
    synergy_analysis = analyze_relic_synergies(relics)

    # Generate recommendations
    recommendations = generate_build_recommendations(
      relics,
      calculation_result,
      context,
      warnings
    )

    {
      performance_rating: performance_rating,
      total_multiplier: total_multiplier,
      difficulty_rating: summary[:average_difficulty],
      synergy_analysis: synergy_analysis,
      recommendations: recommendations,
      warnings: warnings,
      breakdown: calculation_result[:breakdown],
      metadata: {
        relic_distribution: {
          categories: summary[:categories],
          rarities: summary[:rarities],
          qualities: summary[:qualities]
        },
        effect_count: summary[:total_effects],
        has_conflicts: summary[:has_conflicts]
      }
    }
  end

  def calculate_performance_rating(total_multiplier, summary)
    base_score = case total_multiplier
    when 0...1.2
                  "poor"
    when 1.2...1.5
                  "below_average"
    when 1.5...2.0
                  "average"
    when 2.0...2.5
                  "good"
    when 2.5...3.0
                  "excellent"
    else
                  "exceptional"
    end

    # Adjust for difficulty
    difficulty_modifier = case summary[:average_difficulty]
    when 0...3
                           "easy"
    when 3...6
                           "moderate"
    when 6...8
                           "hard"
    else
                           "very_hard"
    end

    {
      overall: base_score,
      difficulty: difficulty_modifier,
      multiplier_value: total_multiplier,
      difficulty_value: summary[:average_difficulty]
    }
  end

  def analyze_relic_synergies(relics)
    synergies = []
    effect_groups = {}

    # Group effects by type
    relics.each do |relic|
      relic[:effects].each do |effect|
        effect_type = effect[:effect_type]
        effect_groups[effect_type] ||= []
        effect_groups[effect_type] << {
          relic_name: relic[:name],
          effect_name: effect[:name],
          value: effect[:value],
          stacking_rule: effect[:stacking_rule]
        }
      end
    end

    # Identify synergistic combinations
    effect_groups.each do |effect_type, effects|
      if effects.length > 1
        total_value = effects.sum { |e| e[:value] }
        synergies << {
          type: effect_type,
          relic_count: effects.length,
          contributing_relics: effects.map { |e| e[:relic_name] }.uniq,
          total_value: total_value,
          synergy_strength: calculate_synergy_strength(effects)
        }
      end
    end

    synergies.sort_by { |s| -s[:synergy_strength] }
  end

  def calculate_synergy_strength(effects)
    # Simple synergy strength calculation
    base_strength = effects.length * 10
    value_bonus = effects.sum { |e| e[:value] } * 0.1

    # Bonus for additive stacking
    additive_bonus = effects.count { |e| e[:stacking_rule] == "additive" } * 5

    (base_strength + value_bonus + additive_bonus).round(2)
  end

  def generate_build_recommendations(relics, calculation_result, context, warnings)
    recommendations = []

    # Performance-based recommendations
    if calculation_result[:total_multiplier] < 1.5
      recommendations << {
        type: "performance",
        priority: "high",
        message: "Consider adding more attack-boosting relics for better damage output",
        suggestion: "Look for relics with attack_multiplier or attack_percentage effects"
      }
    end

    # Difficulty-based recommendations
    total_difficulty = relics.sum { |r| r[:metadata][:obtainment_difficulty] }
    if total_difficulty > 40
      recommendations << {
        type: "difficulty",
        priority: "medium",
        message: "This build requires very difficult relics to obtain",
        suggestion: "Consider substituting some legendary relics with easier alternatives"
      }
    end

    # Warning-based recommendations
    warnings.each do |warning|
      case warning[:type]
      when "complex_conditions"
        recommendations << {
          type: "complexity",
          priority: "low",
          message: "This build has many conditional effects that may be hard to manage",
          suggestion: "Consider simplifying by using relics with unconditional effects"
        }
      when "many_legendaries"
        recommendations << {
          type: "rarity",
          priority: "medium",
          message: "This build requires many legendary relics",
          suggestion: "Mix in some epic or rare relics for easier acquisition"
        }
      end
    end

    recommendations
  end

  def generate_meta_builds_for_style(combat_style, constraints, context)
    # This would typically come from a curated list or ML-generated meta builds
    # For now, return some hardcoded examples based on combat style

    base_builds = case combat_style
    when "melee"
                    [
                      {
                        name: "High DPS Melee",
                        description: "Focus on raw attack power with straightforward relics",
                        relic_ids: [ "physical-attack-up", "improved-straight-sword", "initial-attack-buff" ],
                        tags: [ "beginner-friendly", "high-damage" ]
                      },
                      {
                        name: "Critical Strike Build",
                        description: "Maximize critical damage potential",
                        relic_ids: [ "improved-critical-hits", "three-weapon-bonus", "physical-attack-up" ],
                        tags: [ "critical", "advanced" ]
                      }
                    ]
    when "ranged"
                    [
                      {
                        name: "Archer Build",
                        description: "Optimized for ranged combat",
                        relic_ids: [ "physical-attack-up", "improved-critical-hits" ],
                        tags: [ "ranged", "balanced" ]
                      }
                    ]
    when "magic"
                    [
                      {
                        name: "Mage Build",
                        description: "Magic-focused damage dealer",
                        relic_ids: [ "improved-critical-hits", "physical-attack-up" ],
                        tags: [ "magic", "versatile" ]
                      }
                    ]
    else
                    []
    end

    # Calculate performance for each build
    base_builds.map do |build|
      begin
        calculation_result = CalculationService.calculate_attack_multiplier(
          build[:relic_ids],
          context.merge("combatStyle" => combat_style)
        )

        build.merge(
          performance: {
            total_multiplier: calculation_result[:total_multiplier],
            rating: calculate_performance_rating(
              calculation_result[:total_multiplier],
              { average_difficulty: 5.0 }
            )[:overall]
          },
          difficulty_estimate: estimate_build_difficulty(build[:relic_ids])
        )
      rescue => e
        build.merge(
          performance: { error: e.message },
          difficulty_estimate: "unknown"
        )
      end
    end
  end

  def estimate_build_difficulty(relic_ids)
    # Rough estimation based on relic names
    # In a real implementation, this would query the database
    difficulty_estimates = {
      "physical-attack-up" => 3,
      "improved-straight-sword" => 4,
      "initial-attack-buff" => 2,
      "improved-critical-hits" => 6,
      "three-weapon-bonus" => 7
    }

    total_difficulty = relic_ids.sum { |id| difficulty_estimates[id] || 5 }
    average_difficulty = total_difficulty.to_f / relic_ids.length

    case average_difficulty
    when 0...3
      "easy"
    when 3...5
      "moderate"
    when 5...7
      "hard"
    else
      "very_hard"
    end
  end

  def parse_batch_combinations
    combinations_param = params[:combinations]

    return [] unless combinations_param.present?

    case combinations_param
    when String
      begin
        parsed = JSON.parse(combinations_param)
        Array(parsed)
      rescue JSON::ParserError
        []
      end
    when Array
      combinations_param
    else
      []
    end.map.with_index do |combination, index|
      {
        id: combination["id"] || index,
        relic_ids: Array(combination["relic_ids"] || combination["relicIds"]).map(&:to_s),
        context: parse_combination_context(combination["context"] || {})
      }
    end
  end

  def parse_combination_context(context_param)
    case context_param
    when String
      begin
        JSON.parse(context_param)
      rescue JSON::ParserError
        {}
      end
    when Hash
      context_param
    else
      {}
    end
  end

  def parse_comparison_combinations
    combinations_param = params[:combinations]

    return [] unless combinations_param.present?

    case combinations_param
    when String
      begin
        parsed = JSON.parse(combinations_param)
        Array(parsed)
      rescue JSON::ParserError
        []
      end
    when Array
      combinations_param
    else
      []
    end.map.with_index do |combination, index|
      {
        id: combination["id"] || combination["combination_id"] || index,
        name: combination["name"] || "Build #{index + 1}",
        relic_ids: Array(combination["relic_ids"] || combination["relicIds"]).map(&:to_s),
        context: parse_combination_context(combination["context"] || {})
      }
    end
  end

  def generate_comparison_analysis(combination, calculation_result, index)
    total_multiplier = calculation_result[:total_multiplier]

    # Calculate difficulty and cost estimates
    relic_count = combination[:relic_ids].length
    difficulty_estimate = estimate_combination_difficulty(combination[:relic_ids])

    {
      performance_score: calculate_performance_score(total_multiplier),
      difficulty_rating: difficulty_estimate,
      efficiency_ratio: total_multiplier / relic_count,
      strengths: identify_build_strengths(calculation_result),
      weaknesses: identify_build_weaknesses(calculation_result),
      unique_features: identify_unique_features(combination)
    }
  end

  def determine_comparison_winner(comparison_results)
    # Determine winner based on multiple criteria
    best_performance = comparison_results.max_by { |r| r[:performance][:total_multiplier] }
    best_efficiency = comparison_results.max_by { |r| r[:analysis][:efficiency_ratio] }
    easiest_build = comparison_results.min_by { |r| r[:analysis][:difficulty_rating] }

    {
      overall_winner: {
        combination_id: best_performance[:combination_id],
        name: best_performance[:name],
        reason: "Highest total damage multiplier",
        total_multiplier: best_performance[:performance][:total_multiplier]
      },
      most_efficient: {
        combination_id: best_efficiency[:combination_id],
        name: best_efficiency[:name],
        reason: "Best damage per relic ratio",
        efficiency_ratio: best_efficiency[:analysis][:efficiency_ratio]
      },
      easiest_to_build: {
        combination_id: easiest_build[:combination_id],
        name: easiest_build[:name],
        reason: "Lowest difficulty requirements",
        difficulty_rating: easiest_build[:analysis][:difficulty_rating]
      }
    }
  end

  def generate_performance_rankings(comparison_results)
    # Rank by different metrics
    {
      by_total_damage: comparison_results.sort_by { |r| -r[:performance][:total_multiplier] }
                                      .map.with_index { |r, i| { rank: i + 1, **r.slice(:combination_id, :name), total_multiplier: r[:performance][:total_multiplier] } },
      by_efficiency: comparison_results.sort_by { |r| -r[:analysis][:efficiency_ratio] }
                                    .map.with_index { |r, i| { rank: i + 1, **r.slice(:combination_id, :name), efficiency_ratio: r[:analysis][:efficiency_ratio] } },
      by_difficulty: comparison_results.sort_by { |r| r[:analysis][:difficulty_rating] }
                                    .map.with_index { |r, i| { rank: i + 1, **r.slice(:combination_id, :name), difficulty_rating: r[:analysis][:difficulty_rating] } }
    }
  end

  def generate_comparison_summary(comparison_results)
    multipliers = comparison_results.map { |r| r[:performance][:total_multiplier] }

    {
      total_builds_compared: comparison_results.length,
      performance_range: {
        highest: multipliers.max,
        lowest: multipliers.min,
        average: (multipliers.sum / multipliers.length.to_f).round(3)
      },
      difficulty_distribution: comparison_results.group_by { |r|
        case r[:analysis][:difficulty_rating]
        when 0...3 then "easy"
        when 3...6 then "moderate"
        when 6...8 then "hard"
        else "very_hard"
        end
      }.transform_values(&:count),
      recommendations: generate_summary_recommendations(comparison_results)
    }
  end

  def calculate_performance_score(total_multiplier)
    # Normalize multiplier to a 0-100 score
    case total_multiplier
    when 0...1.2
      (total_multiplier * 41.67).round(1) # 0-50 range
    when 1.2...2.0
      (50 + (total_multiplier - 1.2) * 62.5).round(1) # 50-100 range
    else
      [ 100 + (total_multiplier - 2.0) * 25, 150 ].min.round(1) # 100+ range, capped at 150
    end
  end

  def estimate_combination_difficulty(relic_ids)
    # Simplified difficulty estimation
    difficulty_map = {
      "physical-attack-up" => 3,
      "improved-straight-sword" => 5,
      "initial-attack-buff" => 7,
      "three-weapon-bonus" => 6,
      "improved-critical-hits" => 9
    }

    total_difficulty = relic_ids.sum { |id| difficulty_map[id] || 5 }
    total_difficulty.to_f / relic_ids.length
  end

  def identify_build_strengths(calculation_result)
    strengths = []
    total_multiplier = calculation_result[:total_multiplier]

    strengths << "High damage output" if total_multiplier >= 2.0
    strengths << "Excellent damage potential" if total_multiplier >= 2.5
    strengths << "Balanced performance" if total_multiplier.between?(1.5, 2.0)

    strengths
  end

  def identify_build_weaknesses(calculation_result)
    weaknesses = []
    total_multiplier = calculation_result[:total_multiplier]

    weaknesses << "Low damage output" if total_multiplier < 1.3
    weaknesses << "Below average performance" if total_multiplier.between?(1.3, 1.5)

    weaknesses
  end

  def identify_unique_features(combination)
    features = []
    relic_count = combination[:relic_ids].length

    features << "Minimal relic build" if relic_count <= 3
    features << "Complex multi-relic build" if relic_count >= 7
    features << "Critical-focused build" if combination[:relic_ids].any? { |id| id.include?("critical") }
    features << "Weapon-specific build" if combination[:relic_ids].any? { |id| id.include?("sword") }

    features
  end

  def generate_summary_recommendations(comparison_results)
    recommendations = []

    # Find best overall performer
    best = comparison_results.max_by { |r| r[:performance][:total_multiplier] }
    recommendations << "For maximum damage, consider '#{best[:name]}' with #{best[:performance][:total_multiplier].round(2)}x multiplier"

    # Find most efficient
    most_efficient = comparison_results.max_by { |r| r[:analysis][:efficiency_ratio] }
    recommendations << "For best efficiency, '#{most_efficient[:name]}' provides #{most_efficient[:analysis][:efficiency_ratio].round(2)} damage per relic"

    # Find easiest to build
    easiest = comparison_results.min_by { |r| r[:analysis][:difficulty_rating] }
    recommendations << "For easier acquisition, start with '#{easiest[:name]}' (difficulty: #{easiest[:analysis][:difficulty_rating].round(1)})"

    recommendations
  end
end
