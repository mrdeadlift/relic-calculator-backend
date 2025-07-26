FactoryBot.define do
  factory :relic_effect do
    association :relic
    sequence(:name) { |n| "Effect #{n}" }
    effect_type { [ 'attack_multiplier', 'attack_flat', 'critical_chance', 'critical_multiplier' ].sample }
    value { rand(1.0..5.0).round(2) }
    stacking_rule { [ 'additive', 'multiplicative', 'overwrite', 'unique' ].sample }
    description { Faker::Lorem.sentence }
    damage_types { [ 'physical' ] }
    conditions { [] }

    trait :attack_multiplier do
      name { 'Attack Multiplier' }
      effect_type { 'attack_multiplier' }
      value { rand(1.1..2.5).round(2) }
      stacking_rule { 'multiplicative' }
      description { 'Increases attack damage by a multiplier' }
    end

    trait :attack_flat do
      name { 'Flat Attack Bonus' }
      effect_type { 'attack_flat' }
      value { rand(10..100) }
      stacking_rule { 'additive' }
      description { 'Adds flat attack damage' }
    end

    trait :critical_chance do
      name { 'Critical Chance' }
      effect_type { 'critical_chance' }
      value { rand(5..25) }
      stacking_rule { 'additive' }
      description { 'Increases critical hit chance' }
      damage_types { [ 'physical', 'magical' ] }
    end

    trait :critical_multiplier do
      name { 'Critical Multiplier' }
      effect_type { 'critical_multiplier' }
      value { rand(12..30) }
      stacking_rule { 'additive' }
      description { 'Increases critical hit damage' }
      damage_types { [ 'physical', 'magical' ] }
    end

    trait :elemental_damage do
      name { 'Elemental Damage' }
      effect_type { 'elemental_damage' }
      value { rand(10..50) }
      stacking_rule { 'additive' }
      description { 'Adds elemental damage' }
      damage_types { [ 'fire', 'ice', 'lightning' ] }
    end

    trait :weapon_specific do
      name { 'Weapon Specific Bonus' }
      effect_type { 'weapon_specific' }
      value { rand(5..15) }
      stacking_rule { 'multiplicative' }
      description { 'Bonus damage for specific weapon types' }
      conditions { [ { type: 'weapon_type', value: 'sword', description: 'Requires sword equipped' } ] }
    end

    trait :conditional_damage do
      name { 'Conditional Damage' }
      effect_type { 'conditional_damage' }
      value { rand(10..25) }
      stacking_rule { 'multiplicative' }
      description { 'Bonus damage under specific conditions' }
      conditions { [ { type: 'health_threshold', value: 50, description: 'When health is below 50%' } ] }
    end

    trait :physical_damage do
      name { 'Physical Damage Boost' }
      effect_type { 'attack_percentage' }
      value { 2 }
      stacking_rule { 'additive' }
      description { '+2% physical attack power per level' }
      damage_types { [ 'physical' ] }
      conditions { [
        {
          type: 'equipment_count',
          value: 'character_level',
          description: 'Scales with character level'
        }
      ] }
    end

    trait :with_complex_conditions do
      conditions { [
        { type: 'weapon_type', value: 'sword', description: 'Requires sword' },
        { type: 'health_threshold', value: 75, description: 'When health is above 75%' },
        { type: 'chain_position', value: 1, description: 'First attack in combo' }
      ] }
    end
  end
end
