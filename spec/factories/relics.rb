FactoryBot.define do
  factory :relic do
    sequence(:name) { |n| "Test Relic #{n}" }
    description { Faker::Lorem.paragraph(sentence_count: 2) }
    category { ['Attack', 'Defense', 'Utility', 'Critical', 'Elemental'].sample }
    rarity { ['common', 'rare', 'epic', 'legendary'].sample }
    quality { ['Delicate', 'Polished', 'Grand'].sample }
    icon_url { "/icons/test-relic-#{name.downcase.gsub(' ', '-')}.png" }
    obtainment_difficulty { rand(1..10) }
    conflicts { [] }

    trait :common do
      rarity { 'common' }
      obtainment_difficulty { rand(1..3) }
    end

    trait :rare do
      rarity { 'rare' }
      obtainment_difficulty { rand(3..6) }
    end

    trait :epic do
      rarity { 'epic' }
      obtainment_difficulty { rand(6..8) }
    end

    trait :legendary do
      rarity { 'legendary' }
      obtainment_difficulty { rand(8..10) }
    end

    trait :attack_focused do
      category { 'Attack' }
    end

    trait :with_effects do
      after(:create) do |relic|
        create_list(:relic_effect, 2, relic: relic)
      end
    end

    trait :with_conflicts do
      after(:create) do |relic|
        conflicting_relic = create(:relic)
        relic.update(conflicts: [conflicting_relic.id])
      end
    end

    # Specific relic configurations for testing
    factory :physical_attack_relic do
      name { 'Physical Attack Up' }
      description { 'Increases physical attack power based on character level' }
      category { 'Attack' }
      rarity { 'common' }
      quality { 'Polished' }
      obtainment_difficulty { 3 }

      after(:create) do |relic|
        create(:relic_effect, :physical_damage, relic: relic)
      end
    end

    factory :critical_hit_relic do
      name { 'Improved Critical Hits' }
      description { 'Multi-tier critical hit damage enhancement' }
      category { 'Critical' }
      rarity { 'legendary' }
      quality { 'Grand' }
      obtainment_difficulty { 9 }

      after(:create) do |relic|
        create_list(:relic_effect, 3, :critical_multiplier, relic: relic)
      end
    end
  end
end