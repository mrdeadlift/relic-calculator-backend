FactoryBot.define do
  factory :build_relic do
    association :build
    association :relic
    position { 1 }

    trait :with_custom_conditions do
      custom_conditions { { 'enemy_type' => 'boss', 'player_health' => 80 } }
    end

    trait :at_position do |position_value|
      position { position_value }
    end
  end
end