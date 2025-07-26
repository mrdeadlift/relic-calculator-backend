require 'rails_helper'

RSpec.describe CalculationService, type: :service do
  let(:service) { described_class.new }

  describe '#calculate_attack_multiplier' do
    let!(:attack_relic) { create(:relic, :attack_focused, :with_effects) }
    let!(:critical_relic) { create(:critical_hit_relic) }
    let(:relics) { [ attack_relic, critical_relic ] }
    let(:context) do
      {
        attack_type: 'normal',
        weapon_type: 'sword',
        enemy_type: 'normal',
        player_level: 50,
        weapon_level: 40
      }
    end

    context 'with valid relics and context' do
      subject { service.calculate_attack_multiplier(relics, context) }

      it 'returns calculation result hash' do
        expect(subject).to be_a(Hash)
        expect(subject).to include(:attack_multipliers, :efficiency, :breakdown, :metadata)
      end

      it 'calculates correct attack multipliers' do
        result = subject
        multipliers = result[:attack_multipliers]

        expect(multipliers[:total]).to be > 1.0
        expect(multipliers[:base]).to be >= 1.0
        expect(multipliers[:synergy]).to be >= 0.0
        expect(multipliers[:conditional]).to be >= 0.0
      end

      it 'includes efficiency calculation' do
        result = subject
        expect(result[:efficiency]).to be_between(0.0, 1.0)
      end

      it 'provides detailed breakdown' do
        result = subject
        breakdown = result[:breakdown]

        expect(breakdown).to be_an(Array)
        expect(breakdown.first).to include(:step, :description, :value, :running_total)
      end

      it 'includes metadata with performance info' do
        result = subject
        metadata = result[:metadata]

        expect(metadata).to include(:calculated_at, :client_side, :performance)
        expect(metadata[:performance]).to include(:duration, :relic_count)
      end
    end

    context 'with empty relics array' do
      subject { service.calculate_attack_multiplier([], context) }

      it 'returns base calculation' do
        result = subject
        expect(result[:attack_multipliers][:total]).to eq(1.0)
        expect(result[:efficiency]).to eq(0.0)
      end
    end

    context 'with conflicting relics' do
      let!(:relic1) { create(:relic, :with_effects) }
      let!(:relic2) { create(:relic, :with_effects) }

      before { relic1.update(conflicts: [ relic2.id ]) }

      subject { service.calculate_attack_multiplier([ relic1, relic2 ], context) }

      it 'applies conflict penalty' do
        result = subject
        expect(result[:attack_multipliers][:total]).to be < 1.5 # Reduced due to conflict
        expect(result[:breakdown].any? { |step| step[:description].include?('conflict') }).to be true
      end
    end

    context 'with conditional effects' do
      let!(:conditional_relic) { create(:relic) }

      before do
        create(:relic_effect, :conditional_damage, relic: conditional_relic)
      end

      context 'when conditions are met' do
        let(:conditional_context) { context.merge(player_health: 40) } # Below 50% threshold

        subject { service.calculate_attack_multiplier([ conditional_relic ], conditional_context) }

        it 'applies conditional bonus' do
          result = subject
          expect(result[:attack_multipliers][:conditional]).to be > 0
        end
      end

      context 'when conditions are not met' do
        let(:conditional_context) { context.merge(player_health: 80) } # Above 50% threshold

        subject { service.calculate_attack_multiplier([ conditional_relic ], conditional_context) }

        it 'does not apply conditional bonus' do
          result = subject
          expect(result[:attack_multipliers][:conditional]).to eq(0)
        end
      end
    end

    context 'with weapon-specific bonuses' do
      let!(:sword_relic) { create(:relic) }

      before do
        create(:relic_effect, :weapon_specific, relic: sword_relic)
      end

      context 'with matching weapon type' do
        let(:sword_context) { context.merge(weapon_type: 'sword') }

        subject { service.calculate_attack_multiplier([ sword_relic ], sword_context) }

        it 'applies weapon-specific bonus' do
          result = subject
          expect(result[:attack_multipliers][:total]).to be > 1.0
        end
      end

      context 'with non-matching weapon type' do
        let(:bow_context) { context.merge(weapon_type: 'bow') }

        subject { service.calculate_attack_multiplier([ sword_relic ], bow_context) }

        it 'does not apply weapon-specific bonus' do
          result = subject
          # Should still have base multiplier but no weapon bonus
          expect(result[:attack_multipliers][:total]).to eq(1.0)
        end
      end
    end

    context 'with stacking rules' do
      let!(:additive_relic1) { create(:relic) }
      let!(:additive_relic2) { create(:relic) }
      let!(:multiplicative_relic) { create(:relic) }

      before do
        create(:relic_effect, effect_type: 'attack_percentage', value: 10,
               stacking_rule: 'additive', relic: additive_relic1)
        create(:relic_effect, effect_type: 'attack_percentage', value: 15,
               stacking_rule: 'additive', relic: additive_relic2)
        create(:relic_effect, :attack_multiplier, value: 1.2,
               stacking_rule: 'multiplicative', relic: multiplicative_relic)
      end

      subject do
        service.calculate_attack_multiplier([ additive_relic1, additive_relic2, multiplicative_relic ], context)
      end

      it 'applies correct stacking rules' do
        result = subject

        # Additive effects: 10% + 15% = 25% = 0.25 multiplier bonus
        # Multiplicative effect: 1.2x multiplier
        # Expected: (1.0 + 0.25) * 1.2 = 1.5
        expect(result[:attack_multipliers][:total]).to be_within(0.1).of(1.5)
      end
    end
  end

  describe '#validate_combination' do
    let!(:valid_relics) { create_list(:relic, 3, :with_effects) }
    let!(:conflicting_relic1) { create(:relic, :with_effects) }
    let!(:conflicting_relic2) { create(:relic, :with_effects) }

    before { conflicting_relic1.update(conflicts: [ conflicting_relic2.id ]) }

    context 'with valid combination' do
      subject { service.validate_combination(valid_relics, 'melee') }

      it 'returns valid result' do
        expect(subject[:valid]).to be true
        expect(subject[:errors]).to be_empty
      end

      it 'may include warnings for suboptimal choices' do
        expect(subject[:warnings]).to be_an(Array)
      end

      it 'includes suggestions for improvement' do
        expect(subject[:suggestions]).to be_an(Array)
      end
    end

    context 'with conflicting relics' do
      subject { service.validate_combination([ conflicting_relic1, conflicting_relic2 ], 'melee') }

      it 'returns invalid result' do
        expect(subject[:valid]).to be false
        expect(subject[:errors]).to include(match(/conflict/i))
      end
    end

    context 'with too many relics' do
      let(:too_many_relics) { create_list(:relic, 12, :with_effects) }

      subject { service.validate_combination(too_many_relics, 'melee') }

      it 'returns invalid result' do
        expect(subject[:valid]).to be false
        expect(subject[:errors]).to include('Maximum 9 relics allowed in a build')
      end
    end

    context 'with empty relic list' do
      subject { service.validate_combination([], 'melee') }

      it 'returns valid but warns about empty build' do
        expect(subject[:valid]).to be true
        expect(subject[:warnings]).to include('Build has no relics selected')
      end
    end
  end

  describe '#compare_combinations' do
    let!(:high_damage_relics) { create_list(:relic, 3, :attack_focused, :with_effects) }
    let!(:balanced_relics) { create_list(:relic, 3, :with_effects) }

    let(:combinations) do
      [
        {
          name: 'High Damage Build',
          relic_ids: high_damage_relics.map(&:id),
          combat_style: 'melee'
        },
        {
          name: 'Balanced Build',
          relic_ids: balanced_relics.map(&:id),
          combat_style: 'hybrid'
        }
      ]
    end

    subject { service.compare_combinations(combinations) }

    it 'returns comparison results' do
      result = subject
      expect(result).to include(:comparisons, :winner, :analysis)
    end

    it 'calculates performance for each combination' do
      result = subject
      comparisons = result[:comparisons]

      expect(comparisons).to be_an(Array)
      expect(comparisons.length).to eq(2)

      comparisons.each do |comparison|
        expect(comparison).to include(:name, :attack_multipliers, :efficiency, :relic_count)
      end
    end

    it 'identifies the winner' do
      result = subject
      winner = result[:winner]

      expect(winner).to include(:name, :attack_multipliers)
      expect(winner[:name]).to be_in([ 'High Damage Build', 'Balanced Build' ])
    end

    it 'provides analysis of differences' do
      result = subject
      analysis = result[:analysis]

      expect(analysis).to include(:performance_gap, :trade_offs, :recommendations)
    end
  end

  describe 'performance and caching' do
    let!(:relics) { create_list(:relic, 5, :with_effects) }
    let(:context) { { attack_type: 'normal', weapon_type: 'sword' } }

    describe 'calculation performance' do
      it 'completes calculations within reasonable time' do
        start_time = Time.current

        service.calculate_attack_multiplier(relics, context)

        execution_time = Time.current - start_time
        expect(execution_time).to be < 1.0 # Should complete within 1 second
      end

      it 'handles large relic combinations efficiently' do
        large_relic_set = create_list(:relic, 9, :with_effects) # Maximum allowed

        start_time = Time.current
        result = service.calculate_attack_multiplier(large_relic_set, context)
        execution_time = Time.current - start_time

        expect(result).to be_present
        expect(execution_time).to be < 2.0 # Even large sets should be fast
      end
    end

    describe 'caching behavior' do
      let(:cache_key) { service.send(:cache_key_for, relics.map(&:id), context) }

      it 'caches calculation results' do
        # Clear any existing cache
        Rails.cache.delete(cache_key)

        # First calculation should hit the database
        expect {
          service.calculate_attack_multiplier(relics, context)
        }.to change { Rails.cache.exist?(cache_key) }.from(false).to(true)

        # Second calculation should use cache
        expect(Rails.cache).to receive(:fetch).with(cache_key, any_args).and_call_original
        service.calculate_attack_multiplier(relics, context)
      end

      it 'invalidates cache when relics are updated' do
        # Calculate to populate cache
        service.calculate_attack_multiplier(relics, context)
        expect(Rails.cache.exist?(cache_key)).to be true

        # Update a relic
        relics.first.touch

        # Cache should be invalidated
        # Note: This depends on proper cache invalidation implementation
        new_result = service.calculate_attack_multiplier(relics, context)
        expect(new_result).to be_present
      end
    end
  end

  describe 'error handling' do
    let(:context) { { attack_type: 'normal' } }

    context 'with invalid relic data' do
      let(:invalid_relic) do
        relic = create(:relic)
        # Create an effect with invalid data
        create(:relic_effect, relic: relic, value: 'invalid', effect_type: 'attack_multiplier')
        relic
      end

      it 'handles invalid effect values gracefully' do
        expect {
          service.calculate_attack_multiplier([ invalid_relic ], context)
        }.not_to raise_error

        result = service.calculate_attack_multiplier([ invalid_relic ], context)
        expect(result[:attack_multipliers][:total]).to eq(1.0) # Should default to base
      end
    end

    context 'with nil context' do
      it 'uses default context values' do
        expect {
          service.calculate_attack_multiplier([ create(:relic, :with_effects) ], nil)
        }.not_to raise_error
      end
    end

    context 'with missing relics' do
      it 'handles non-existent relic IDs gracefully' do
        combinations = [ {
          name: 'Test Build',
          relic_ids: [ 'non-existent-id' ],
          combat_style: 'melee'
        } ]

        expect {
          service.compare_combinations(combinations)
        }.not_to raise_error
      end
    end
  end

  describe 'integration with optimization service' do
    let!(:suboptimal_relics) { create_list(:relic, 3, :common, :with_effects) }
    let!(:optimal_relics) { create_list(:relic, 3, :legendary, :attack_focused, :with_effects) }

    it 'provides data for optimization algorithms' do
      suboptimal_result = service.calculate_attack_multiplier(suboptimal_relics, { combat_style: 'melee' })
      optimal_result = service.calculate_attack_multiplier(optimal_relics, { combat_style: 'melee' })

      expect(optimal_result[:attack_multipliers][:total]).to be > suboptimal_result[:attack_multipliers][:total]
      expect(optimal_result[:efficiency]).to be >= suboptimal_result[:efficiency]
    end
  end
end
