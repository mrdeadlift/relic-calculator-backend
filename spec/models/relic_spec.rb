require 'rails_helper'

RSpec.describe Relic, type: :model do
  describe 'validations' do
    subject { build(:relic) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:category) }
    it { should validate_presence_of(:rarity) }
    it { should validate_presence_of(:quality) }
    it { should validate_presence_of(:icon_url) }
    it { should validate_presence_of(:obtainment_difficulty) }

    it { should validate_uniqueness_of(:name) }

    it { should validate_inclusion_of(:category).in_array([ 'Attack', 'Defense', 'Utility', 'Critical', 'Elemental' ]) }
    it { should validate_inclusion_of(:rarity).in_array([ 'common', 'rare', 'epic', 'legendary' ]) }
    it { should validate_inclusion_of(:quality).in_array([ 'Delicate', 'Polished', 'Grand' ]) }

    it { should validate_numericality_of(:obtainment_difficulty).is_greater_than_or_equal_to(1).is_less_than_or_equal_to(10) }

    describe 'conflicts validation' do
      it 'validates that conflicts contain valid relic IDs' do
        existing_relic = create(:relic)
        relic = build(:relic, conflicts: [ existing_relic.id ])
        expect(relic).to be_valid
      end

      it 'is invalid when conflicts contain non-existent IDs' do
        relic = build(:relic, conflicts: [ 'non-existent-id' ])
        expect(relic).not_to be_valid
        expect(relic.errors[:conflicts]).to include('contains invalid relic IDs')
      end

      it 'prevents self-referencing conflicts' do
        relic = create(:relic)
        relic.conflicts = [ relic.id ]
        expect(relic).not_to be_valid
        expect(relic.errors[:conflicts]).to include('cannot contain self-reference')
      end
    end
  end

  describe 'associations' do
    it { should have_many(:relic_effects).dependent(:destroy) }
    it { should have_many(:build_relics).dependent(:destroy) }
    it { should have_many(:builds).through(:build_relics) }
  end

  describe 'scopes' do
    let!(:common_relic) { create(:relic, :common) }
    let!(:rare_relic) { create(:relic, :rare) }
    let!(:epic_relic) { create(:relic, :epic) }
    let!(:attack_relic) { create(:relic, category: 'Attack') }
    let!(:defense_relic) { create(:relic, category: 'Defense') }

    describe '.by_category' do
      it 'filters relics by category' do
        expect(Relic.by_category('Attack')).to include(attack_relic)
        expect(Relic.by_category('Attack')).not_to include(defense_relic)
      end
    end

    describe '.by_rarity' do
      it 'filters relics by rarity' do
        expect(Relic.by_rarity('common')).to include(common_relic)
        expect(Relic.by_rarity('common')).not_to include(rare_relic)
      end
    end

    describe '.by_difficulty_range' do
      it 'filters relics by difficulty range' do
        easy_relic = create(:relic, obtainment_difficulty: 2)
        hard_relic = create(:relic, obtainment_difficulty: 8)

        expect(Relic.by_difficulty_range(1, 5)).to include(easy_relic)
        expect(Relic.by_difficulty_range(1, 5)).not_to include(hard_relic)
      end
    end

    describe '.search_by_name' do
      it 'searches relics by name' do
        sword_relic = create(:relic, name: 'Magic Sword Boost')
        bow_relic = create(:relic, name: 'Ancient Bow Power')

        expect(Relic.search_by_name('sword')).to include(sword_relic)
        expect(Relic.search_by_name('sword')).not_to include(bow_relic)
      end
    end

    describe '.popular' do
      it 'orders relics by usage count' do
        popular_relic = create(:relic)
        unpopular_relic = create(:relic)

        # Simulate usage by creating builds
        3.times { create(:build, :with_relics).build_relics.first.update(relic: popular_relic) }
        1.times { create(:build, :with_relics).build_relics.first.update(relic: unpopular_relic) }

        expect(Relic.popular.first).to eq(popular_relic)
      end
    end
  end

  describe 'methods' do
    describe '#conflicting_relics' do
      it 'returns relics that conflict with this one' do
        relic1 = create(:relic)
        relic2 = create(:relic)
        relic3 = create(:relic)

        relic1.update(conflicts: [ relic2.id, relic3.id ])

        expect(relic1.conflicting_relics).to include(relic2, relic3)
      end
    end

    describe '#has_conflict_with?' do
      it 'returns true when relics conflict' do
        relic1 = create(:relic)
        relic2 = create(:relic)

        relic1.update(conflicts: [ relic2.id ])

        expect(relic1.has_conflict_with?(relic2)).to be true
        expect(relic2.has_conflict_with?(relic1)).to be false
      end
    end

    describe '#average_effect_value' do
      it 'calculates average value of all effects' do
        relic = create(:relic)
        create(:relic_effect, relic: relic, value: 10)
        create(:relic_effect, relic: relic, value: 20)
        create(:relic_effect, relic: relic, value: 30)

        expect(relic.average_effect_value).to eq(20.0)
      end

      it 'returns 0 when no effects exist' do
        relic = create(:relic)
        expect(relic.average_effect_value).to eq(0)
      end
    end

    describe '#total_attack_multiplier' do
      it 'sums all attack multiplier effects' do
        relic = create(:relic)
        create(:relic_effect, :attack_multiplier, relic: relic, value: 1.5)
        create(:relic_effect, :attack_multiplier, relic: relic, value: 1.3)
        create(:relic_effect, :critical_chance, relic: relic, value: 15) # Should be ignored

        expect(relic.total_attack_multiplier).to eq(2.8)
      end
    end

    describe '#can_be_used_with?' do
      it 'returns false when relics conflict' do
        relic1 = create(:relic)
        relic2 = create(:relic)
        relic1.update(conflicts: [ relic2.id ])

        expect(relic1.can_be_used_with?(relic2)).to be false
      end

      it 'returns true when relics do not conflict' do
        relic1 = create(:relic)
        relic2 = create(:relic)

        expect(relic1.can_be_used_with?(relic2)).to be true
      end
    end

    describe '#difficulty_tier' do
      it 'returns correct difficulty tier' do
        easy_relic = create(:relic, obtainment_difficulty: 2)
        medium_relic = create(:relic, obtainment_difficulty: 5)
        hard_relic = create(:relic, obtainment_difficulty: 8)
        extreme_relic = create(:relic, obtainment_difficulty: 10)

        expect(easy_relic.difficulty_tier).to eq('easy')
        expect(medium_relic.difficulty_tier).to eq('medium')
        expect(hard_relic.difficulty_tier).to eq('hard')
        expect(extreme_relic.difficulty_tier).to eq('extreme')
      end
    end

    describe '#rarity_rank' do
      it 'returns correct rarity rank' do
        common_relic = create(:relic, rarity: 'common')
        rare_relic = create(:relic, rarity: 'rare')
        epic_relic = create(:relic, rarity: 'epic')
        legendary_relic = create(:relic, rarity: 'legendary')

        expect(common_relic.rarity_rank).to eq(1)
        expect(rare_relic.rarity_rank).to eq(2)
        expect(epic_relic.rarity_rank).to eq(3)
        expect(legendary_relic.rarity_rank).to eq(4)
      end
    end

    describe '#usage_statistics' do
      it 'returns usage statistics' do
        relic = create(:relic)
        build1 = create(:build, :with_relics)
        build2 = create(:build, :with_relics)

        # Add relic to builds
        create(:build_relic, build: build1, relic: relic)
        create(:build_relic, build: build2, relic: relic)

        stats = relic.usage_statistics
        expect(stats[:usage_count]).to eq(2)
        expect(stats[:unique_builds]).to eq(2)
      end
    end
  end

  describe 'callbacks' do
    describe 'after_create' do
      it 'logs relic creation' do
        expect(Rails.logger).to receive(:info).with(/Created relic:/)
        create(:relic)
      end
    end

    describe 'before_destroy' do
      it 'prevents deletion when relic is used in builds' do
        relic = create(:relic)
        create(:build_relic, relic: relic)

        expect { relic.destroy }.not_to change(Relic, :count)
        expect(relic.errors[:base]).to include('Cannot delete relic that is used in builds')
      end

      it 'allows deletion when relic is not used' do
        relic = create(:relic)
        expect { relic.destroy }.to change(Relic, :count).by(-1)
      end
    end
  end

  describe 'serialization' do
    it 'serializes conflicts as array' do
      relic = create(:relic, conflicts: [ 'id1', 'id2' ])
      expect(relic.conflicts).to eq([ 'id1', 'id2' ])
    end
  end

  describe 'complex scenarios' do
    describe 'relic with multiple effects and conflicts' do
      let(:relic) do
        create(:relic, :with_effects, :with_conflicts, name: 'Complex Test Relic')
      end

      it 'handles complex relic creation properly' do
        expect(relic.relic_effects.count).to be > 0
        expect(relic.conflicts).not_to be_empty
        expect(relic.average_effect_value).to be > 0
      end
    end

    describe 'relic optimization scenarios' do
      it 'identifies optimal relics for combat styles' do
        melee_relic = create(:relic, :attack_focused, name: 'Melee Master')
        magic_relic = create(:relic, category: 'Elemental', name: 'Spell Weaver')

        create(:relic_effect, :attack_multiplier, relic: melee_relic)
        create(:relic_effect, :elemental_damage, relic: magic_relic)

        # These would be used by optimization algorithms
        expect(melee_relic.category).to eq('Attack')
        expect(magic_relic.category).to eq('Elemental')
      end
    end
  end
end
