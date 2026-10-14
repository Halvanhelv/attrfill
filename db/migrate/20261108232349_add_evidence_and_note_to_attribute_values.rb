class AddEvidenceAndNoteToAttributeValues < ActiveRecord::Migration[8.1]
  def change
    add_column :attribute_values, :evidence, :string
    add_column :attribute_values, :note, :string
  end
end
