class CreateRelics < ActiveRecord::Migration[8.0]
  def change
    create_table :relics do |t|
      t.string :name, null: false
      t.text :description
      t.string :category, null: false
      t.string :rarity, null: false
      t.string :quality, null: false
      t.string :icon_url
      t.integer :obtainment_difficulty, null: false, default: 1
      t.json :conflicts, default: []
      t.boolean :active, default: true
      
      t.timestamps
    end
    
    add_index :relics, :name, unique: true
    add_index :relics, [:category, :rarity]
    add_index :relics, :obtainment_difficulty
    add_index :relics, :active
  end
end