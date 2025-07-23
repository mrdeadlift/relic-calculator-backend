class CreateBuilds < ActiveRecord::Migration[8.0]
  def change
    create_table :builds do |t|
      t.string :name, null: false
      t.text :description
      t.string :combat_style, null: false
      t.string :share_key, unique: true
      t.boolean :is_public, default: false
      t.json :metadata, default: {}
      t.integer :version, default: 1
      
      # User association (for future auth implementation)
      t.references :user, null: true, foreign_key: false
      
      t.timestamps
    end
    
    add_index :builds, :name
    add_index :builds, :share_key, unique: true
    add_index :builds, :combat_style
    add_index :builds, :is_public
    add_index :builds, :user_id
    add_index :builds, :created_at
  end
end