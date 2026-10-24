# A product card as stored, with the values settled for it.
class Card < ApplicationRecord
  belongs_to :batch, optional: true
  has_many :attribute_values, -> { order(:id) }, dependent: :delete_all

  def self.extract!(pipeline: Extraction::Pipeline.new, **fields)
    card = Extraction::Card.build(**fields)
    record!(pipeline.call(card), category: card.category)
  end

  def self.record!(result, batch: nil, category: nil)
    card = create!(batch: batch, external_id: result.card.id, title: result.card.title,
                   description: result.card.description, seller_attributes: result.card.seller_attributes,
                   category: category, detected_category: result.category.name, asked_model: result.asked_model)

    AttributeValue.insert_all!(result.findings.map { |finding| AttributeValue.row(card, finding) })
    card
  end

  def category_title = Extraction::Catalog.current.categories[detected_category]&.label || detected_category

  # The same shape the pipeline returns, for the writer.
  def to_result
    Extraction::Pipeline::Result.new(
      card: Extraction::Card.new(id: external_id || id.to_s, title: title, description: description,
                                 seller_attributes: seller_attributes, category: category),
      category: Extraction::Catalog.current.categories.fetch(detected_category),
      findings: attribute_values.map(&:to_finding), asked_model: asked_model
    )
  end
end
