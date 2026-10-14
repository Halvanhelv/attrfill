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

ActiveRecord::Schema[8.1].define(version: 2026_11_08_232349) do
  create_table "attribute_values", force: :cascade do |t|
    t.integer "card_id", null: false
    t.string "name", null: false
    t.string "value"
    t.string "extracted_value"
    t.text "raw"
    t.float "confidence", default: 0.0, null: false
    t.string "status", null: false
    t.string "source"
    t.string "rule"
    t.json "alternatives", default: [], null: false
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "evidence"
    t.string "note"
    t.index ["card_id"], name: "index_attribute_values_on_card_id"
    t.index ["status"], name: "index_attribute_values_on_status"
  end

  create_table "batches", force: :cascade do |t|
    t.string "name", null: false
    t.string "source_path", null: false
    t.string "status", default: "pending", null: false
    t.integer "cards_count", default: 0, null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "cards", force: :cascade do |t|
    t.integer "batch_id"
    t.string "external_id"
    t.text "title"
    t.text "description"
    t.json "seller_attributes", default: {}, null: false
    t.string "category"
    t.string "detected_category"
    t.boolean "asked_model", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id"], name: "index_cards_on_batch_id"
  end

  create_table "llm_calls", force: :cascade do |t|
    t.string "key", null: false
    t.string "model"
    t.text "question"
    t.json "answer", default: [], null: false
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "duration_ms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_llm_calls_on_key", unique: true
  end

  add_foreign_key "attribute_values", "cards"
  add_foreign_key "cards", "batches"
end
