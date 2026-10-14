class CreateTables < ActiveRecord::Migration[8.1]
  def change
    create_table :batches do |t|
      t.string :name, null: false
      t.string :source_path, null: false
      t.string :status, null: false, default: "pending"
      t.integer :cards_count, null: false, default: 0
      t.text :error
      t.timestamps
    end

    create_table :cards do |t|
      t.references :batch, foreign_key: true
      t.string :external_id
      t.text :title
      t.text :description
      t.json :seller_attributes, null: false, default: {}
      t.string :category
      t.string :detected_category
      t.boolean :asked_model, null: false, default: false
      t.timestamps
    end

    create_table :attribute_values do |t|
      t.references :card, null: false, foreign_key: true
      t.string :name, null: false
      t.string :value
      t.string :extracted_value
      t.text :raw
      t.float :confidence, null: false, default: 0.0
      t.string :status, null: false
      t.string :source
      t.string :rule
      t.json :alternatives, null: false, default: []
      t.datetime :reviewed_at
      t.timestamps
      t.index :status
    end

    create_table :llm_calls do |t|
      t.string :key, null: false, index: { unique: true }
      t.string :model
      t.text :question
      t.json :answer, null: false, default: []
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :duration_ms
      t.timestamps
    end
  end
end
