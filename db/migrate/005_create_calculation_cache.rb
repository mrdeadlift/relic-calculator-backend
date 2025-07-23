class CreateCalculationCache < ActiveRecord::Migration[8.0]
  def change
    create_table :calculation_caches do |t|
      t.string :cache_key, null: false
      t.json :input_data, null: false
      t.json :result_data, null: false
      t.string :version, null: false, default: '1.0'
      t.datetime :expires_at
      t.integer :hit_count, default: 0
      
      t.timestamps
    end
    
    add_index :calculation_caches, :cache_key, unique: true
    add_index :calculation_caches, :expires_at
    add_index :calculation_caches, :version
    add_index :calculation_caches, :created_at
  end
end