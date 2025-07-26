# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 6) do
  create_table "build_relics", force: :cascade do |t|
    t.integer "build_id", null: false
    t.integer "relic_id", null: false
    t.integer "position", default: 0, null: false
    t.json "custom_conditions", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["build_id", "position", "relic_id"], name: "index_build_relics_on_build_id_and_position_and_relic_id"
    t.index ["build_id", "position"], name: "index_build_relics_on_build_id_and_position"
    t.index ["build_id", "relic_id"], name: "index_build_relics_on_build_id_and_relic_id", unique: true
    t.index ["build_id"], name: "index_build_relics_on_build_id"
    t.index ["relic_id"], name: "index_build_relics_on_relic_id"
  end

  create_table "builds", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "combat_style", null: false
    t.string "share_key"
    t.boolean "is_public", default: false
    t.json "metadata", default: {}
    t.integer "version", default: 1
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["combat_style", "is_public", "created_at"], name: "index_builds_on_combat_style_and_is_public_and_created_at"
    t.index ["combat_style"], name: "index_builds_on_combat_style"
    t.index ["created_at"], name: "index_builds_on_created_at"
    t.index ["is_public", "created_at"], name: "index_builds_on_is_public_and_created_at"
    t.index ["is_public"], name: "index_builds_on_is_public"
    t.index ["name"], name: "index_builds_on_name"
    t.index ["share_key"], name: "index_builds_on_share_key", unique: true
    t.index ["user_id"], name: "index_builds_on_user_id"
  end

  create_table "calculation_caches", force: :cascade do |t|
    t.string "cache_key", null: false
    t.json "input_data", null: false
    t.json "result_data", null: false
    t.string "version", default: "1.0", null: false
    t.datetime "expires_at"
    t.integer "hit_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cache_key"], name: "index_calculation_caches_on_cache_key", unique: true
    t.index ["created_at"], name: "index_calculation_caches_on_created_at"
    t.index ["expires_at"], name: "index_calculation_caches_on_expires_at"
    t.index ["version"], name: "index_calculation_caches_on_version"
  end

  create_table "relic_effects", force: :cascade do |t|
    t.integer "relic_id", null: false
    t.string "effect_type", null: false
    t.string "name", null: false
    t.text "description"
    t.decimal "value", precision: 10, scale: 4
    t.string "stacking_rule", default: "additive", null: false
    t.json "conditions", default: []
    t.json "damage_types", default: []
    t.integer "priority", default: 0
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_relic_effects_on_active"
    t.index ["effect_type", "stacking_rule", "active"], name: "idx_on_effect_type_stacking_rule_active_cab6c7390e"
    t.index ["effect_type"], name: "index_relic_effects_on_effect_type"
    t.index ["priority"], name: "index_relic_effects_on_priority"
    t.index ["relic_id", "active", "priority"], name: "index_relic_effects_on_relic_id_and_active_and_priority"
    t.index ["relic_id", "effect_type"], name: "index_relic_effects_on_relic_id_and_effect_type"
    t.index ["relic_id"], name: "index_relic_effects_on_relic_id"
    t.index ["stacking_rule"], name: "index_relic_effects_on_stacking_rule"
  end

  create_table "relics", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "category", null: false
    t.string "rarity", null: false
    t.string "quality", null: false
    t.string "icon_url"
    t.integer "obtainment_difficulty", default: 1, null: false
    t.json "conflicts", default: []
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_relics_on_active"
    t.index ["category", "rarity", "active"], name: "index_relics_on_category_and_rarity_and_active"
    t.index ["category", "rarity"], name: "index_relics_on_category_and_rarity"
    t.index ["description"], name: "index_relics_on_description"
    t.index ["name"], name: "index_relics_on_name", unique: true
    t.index ["obtainment_difficulty"], name: "index_relics_on_obtainment_difficulty"
    t.index ["rarity", "obtainment_difficulty"], name: "index_relics_on_rarity_and_obtainment_difficulty"
  end

  add_foreign_key "build_relics", "builds"
  add_foreign_key "build_relics", "relics"
  add_foreign_key "relic_effects", "relics"
end
