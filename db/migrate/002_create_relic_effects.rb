class CreateRelicEffects < ActiveRecord::Migration[8.0]
  def change
    create_table :relic_effects do |t|
      t.references :relic, null: false, foreign_key: true
      t.string :effect_type, null: false
      t.string :name, null: false
      t.text :description
      t.decimal :value, precision: 10, scale: 4
      t.string :stacking_rule, null: false, default: 'additive'
      t.json :conditions, default: []
      t.json :damage_types, default: []
      t.integer :priority, default: 0
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :relic_effects, [ :relic_id, :effect_type ]
    add_index :relic_effects, :effect_type
    add_index :relic_effects, :stacking_rule
    add_index :relic_effects, :priority
    add_index :relic_effects, :active
  end
end
