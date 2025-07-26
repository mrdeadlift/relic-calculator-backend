# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create sample relics for Nightreign Relic Calculator
puts "Creating sample relics..."

# Physical Attack Up relic
physical_attack_relic = Relic.find_or_create_by!(name: "Physical Attack Up") do |relic|
  relic.description = "Increases physical attack power based on character level"
  relic.category = "Attack"
  relic.rarity = "common"
  relic.quality = "Polished"
  relic.icon_url = "/icons/physical-attack-up.png"
  relic.obtainment_difficulty = 3
  relic.conflicts = []
end

RelicEffect.find_or_create_by!(relic: physical_attack_relic, effect_type: "attack_percentage") do |effect|
  effect.name = "Physical Damage"
  effect.description = "+2% physical attack power per level"
  effect.value = 2.0
  effect.stacking_rule = "additive"
  effect.conditions = [
    {
      id: "per-level",
      type: "equipment_count",
      value: "character_level",
      description: "Scales with character level"
    }
  ]
  effect.damage_types = [ "physical" ]
  effect.priority = 1
end

# Improved Straight Sword relic
straight_sword_relic = Relic.find_or_create_by!(name: "Improved Straight Sword Attack Power") do |relic|
  relic.description = "Enhances straight sword damage significantly"
  relic.category = "Attack"
  relic.rarity = "rare"
  relic.quality = "Grand"
  relic.icon_url = "/icons/improved-straight-sword.png"
  relic.obtainment_difficulty = 5
  relic.conflicts = []
end

RelicEffect.find_or_create_by!(relic: straight_sword_relic, effect_type: "weapon_specific") do |effect|
  effect.name = "Straight Sword Boost"
  effect.description = "+7% straight sword attack power"
  effect.value = 7.0
  effect.stacking_rule = "multiplicative"
  effect.conditions = [
    {
      id: "straight-sword",
      type: "weapon_type",
      value: "straight_sword",
      description: "Requires straight sword equipped"
    }
  ]
  effect.damage_types = [ "physical" ]
  effect.priority = 2
end

# Initial Attack Buff relic
initial_attack_relic = Relic.find_or_create_by!(name: "Initial Attack Buff") do |relic|
  relic.description = "Dramatically increases damage of the first attack in a combo"
  relic.category = "Attack"
  relic.rarity = "epic"
  relic.quality = "Grand"
  relic.icon_url = "/icons/initial-attack-buff.png"
  relic.obtainment_difficulty = 7
  relic.conflicts = []
end

RelicEffect.find_or_create_by!(relic: initial_attack_relic, effect_type: "conditional_damage") do |effect|
  effect.name = "First R1 Boost"
  effect.description = "+13% damage to first R1 in chain"
  effect.value = 13.0
  effect.stacking_rule = "multiplicative"
  effect.conditions = [
    {
      id: "first-attack",
      type: "chain_position",
      value: 1,
      description: "First attack in combo chain"
    }
  ]
  effect.damage_types = [ "physical" ]
  effect.priority = 3
end

# Three Weapon Type Bonus relic
weapon_bonus_relic = Relic.find_or_create_by!(name: "Three Weapon Type Bonus") do |relic|
  relic.description = "Provides damage bonus when using multiple weapons of the same type"
  relic.category = "Attack"
  relic.rarity = "rare"
  relic.quality = "Polished"
  relic.icon_url = "/icons/three-weapon-bonus.png"
  relic.obtainment_difficulty = 6
  relic.conflicts = []
end

RelicEffect.find_or_create_by!(relic: weapon_bonus_relic, effect_type: "conditional_damage") do |effect|
  effect.name = "Weapon Set Bonus"
  effect.description = "+10% damage with 3+ weapons of same type"
  effect.value = 10.0
  effect.stacking_rule = "multiplicative"
  effect.conditions = [
    {
      id: "weapon-count",
      type: "equipment_count",
      value: 3,
      description: "3 or more weapons of same type"
    }
  ]
  effect.damage_types = [ "physical" ]
  effect.priority = 2
end

# Improved Critical Hits relic (legendary with multiple effects)
critical_relic = Relic.find_or_create_by!(name: "Improved Critical Hits") do |relic|
  relic.description = "Multi-tier critical hit damage enhancement"
  relic.category = "Critical"
  relic.rarity = "legendary"
  relic.quality = "Grand"
  relic.icon_url = "/icons/improved-critical-hits.png"
  relic.obtainment_difficulty = 9
  relic.conflicts = []
end

# Critical Multiplier I
RelicEffect.find_or_create_by!(relic: critical_relic, effect_type: "critical_multiplier", name: "Critical Multiplier I") do |effect|
  effect.description = "+12% critical hit damage"
  effect.value = 12.0
  effect.stacking_rule = "additive"
  effect.conditions = [
    {
      id: "critical-hit",
      type: "combat_style",
      value: "critical_strike",
      description: "On critical hits"
    }
  ]
  effect.damage_types = [ "physical", "magical" ]
  effect.priority = 1
end

# Critical Multiplier II
RelicEffect.find_or_create_by!(relic: critical_relic, effect_type: "critical_multiplier", name: "Critical Multiplier II") do |effect|
  effect.description = "+18% critical hit damage"
  effect.value = 18.0
  effect.stacking_rule = "additive"
  effect.conditions = [
    {
      id: "critical-hit-2",
      type: "combat_style",
      value: "critical_strike",
      description: "On critical hits"
    }
  ]
  effect.damage_types = [ "physical", "magical" ]
  effect.priority = 2
end

# Critical Multiplier III
RelicEffect.find_or_create_by!(relic: critical_relic, effect_type: "critical_multiplier", name: "Critical Multiplier III") do |effect|
  effect.description = "+24% critical hit damage"
  effect.value = 24.0
  effect.stacking_rule = "additive"
  effect.conditions = [
    {
      id: "critical-hit-3",
      type: "combat_style",
      value: "critical_strike",
      description: "On critical hits"
    }
  ]
  effect.damage_types = [ "physical", "magical" ]
  effect.priority = 3
end

puts "Sample relics created successfully!"
puts "Total relics: #{Relic.count}"
puts "Total relic effects: #{RelicEffect.count}"
