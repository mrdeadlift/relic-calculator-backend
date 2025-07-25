FactoryBot.define do
  factory :build do
    sequence(:name) { |n| "Test Build #{n}" }
    description { Faker::Lorem.paragraph }
    combat_style { ['melee', 'ranged', 'magic', 'hybrid'].sample }
    is_public { false }
    share_key { nil }

    trait :public do
      is_public { true }
      share_key { SecureRandom.uuid }
    end

    trait :with_relics do
      after(:create) do |build|
        relics = create_list(:relic, 3, :with_effects)
        relics.each_with_index do |relic, index|
          create(:build_relic, build: build, relic: relic, position: index + 1)
        end
      end
    end

    trait :melee_focused do
      name { 'Melee DPS Build' }
      description { 'High damage melee build focused on attack power' }
      combat_style { 'melee' }

      after(:create) do |build|
        # Create attack-focused relics
        attack_relics = create_list(:relic, 2, :attack_focused, :with_effects)
        critical_relic = create(:critical_hit_relic)
        
        [*attack_relics, critical_relic].each_with_index do |relic, index|
          create(:build_relic, build: build, relic: relic, position: index + 1)
        end
      end
    end

    trait :magic_focused do
      name { 'Elemental Magic Build' }
      description { 'Elemental damage focused magic build' }
      combat_style { 'magic' }

      after(:create) do |build|
        relics = create_list(:relic, 3) do |relic|
          relic.category = 'Elemental'
          relic.save!
          create(:relic_effect, :elemental_damage, relic: relic)
        end
        
        relics.each_with_index do |relic, index|
          create(:build_relic, build: build, relic: relic, position: index + 1)
        end
      end
    end

    trait :balanced do
      name { 'Balanced Hybrid Build' }
      description { 'Well-rounded build suitable for various situations' }
      combat_style { 'hybrid' }

      after(:create) do |build|
        attack_relic = create(:relic, :with_effects, category: 'Attack')
        defense_relic = create(:relic, :with_effects, category: 'Defense')
        utility_relic = create(:relic, :with_effects, category: 'Utility')
        
        [attack_relic, defense_relic, utility_relic].each_with_index do |relic, index|
          create(:build_relic, build: build, relic: relic, position: index + 1)
        end
      end
    end

    factory :complex_build do
      name { 'Complex Optimization Build' }
      description { 'A complex build for testing optimization algorithms' }
      combat_style { 'melee' }

      after(:create) do |build|
        # Create a mix of different relic types and rarities
        common_relic = create(:relic, :common, :attack_focused, :with_effects)
        rare_relic = create(:relic, :rare, :with_effects, category: 'Critical')
        epic_relic = create(:relic, :epic, :with_effects, category: 'Elemental')
        legendary_relic = create(:critical_hit_relic)
        
        [common_relic, rare_relic, epic_relic, legendary_relic].each_with_index do |relic, index|
          create(:build_relic, build: build, relic: relic, position: index + 1)
        end
      end
    end
  end
end