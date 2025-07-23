class CreateBuildRelics < ActiveRecord::Migration[8.0]
  def change
    create_table :build_relics do |t|
      t.references :build, null: false, foreign_key: true
      t.references :relic, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.json :custom_conditions, default: {}
      
      t.timestamps
    end
    
    add_index :build_relics, [:build_id, :relic_id], unique: true
    add_index :build_relics, [:build_id, :position]
    add_index :build_relics, :relic_id
  end
end