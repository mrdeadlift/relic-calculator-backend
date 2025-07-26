class AddSearchIndices < ActiveRecord::Migration[8.0]
  def change
    # Full-text search support for relics
    add_index :relics, :name, opclass: :gin_trgm_ops, using: :gin
    add_index :relics, :description, opclass: :gin_trgm_ops, using: :gin

    # Composite indices for common queries
    add_index :relics, [ :category, :rarity, :active ]
    add_index :relics, [ :rarity, :obtainment_difficulty ]

    # Effect-specific indices
    add_index :relic_effects, [ :effect_type, :stacking_rule, :active ]
    add_index :relic_effects, [ :relic_id, :active, :priority ]

    # Build-related indices
    add_index :builds, [ :combat_style, :is_public, :created_at ]
    add_index :builds, [ :is_public, :created_at ]

    # Performance indices for joins
    add_index :build_relics, [ :build_id, :position, :relic_id ]
  end
end
