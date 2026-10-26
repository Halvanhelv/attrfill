# One attribute of a card: the value settled by the pipeline, then by a person when it went to review.
class AttributeValue < ApplicationRecord
  belongs_to :card

  # accepted, review and missing come from the pipeline; a reviewer turns review and missing into the other three.
  enum :status, %w[accepted review missing approved corrected rejected].index_by(&:itself)

  scope :waiting, -> { where(status: %w[review missing]).order(:confidence, :id) }

  def self.row(card, finding)
    now = Time.current
    { card_id: card.id, name: finding.attribute, value: finding.value, extracted_value: finding.value,
      raw: finding.raw, confidence: finding.confidence, status: finding.status, source: finding.source,
      rule: finding.rule, alternatives: finding.alternatives, evidence: finding.evidence, note: finding.note,
      created_at: now, updated_at: now }
  end

  def title = Extraction::Catalog.current.attributes[name]&.label || name

  # What a review form remembers of the value it shows; any later write changes it (ReviewsController#update).
  def version = updated_at&.utc&.iso8601(6).to_s

  # Confirming an empty field confirms that there is no value: it is exported as missing, never as an accepted blank.
  def approve!
    return reject! if value.blank?

    update!(status: "approved", confidence: 1.0, reviewed_at: Time.current)
  end

  # What a reviewer's decision says of the value the pipeline offered: right, wrong, or nothing (nothing was offered,
  # or nobody decided yet).
  def verdict
    return if extracted_value.blank? || !(approved? || corrected? || rejected?)
    return true if approved?
    return false if rejected?

    kind = Extraction::Catalog.current.attributes[name]&.kind
    kind ? kind.same?(extracted_value, value) : extracted_value == value
  end

  def reject! = update!(status: "rejected", value: nil, confidence: 0.0, reviewed_at: Time.current)

  # A person's value is written the same way the pipeline's is.
  def correct!(text)
    return reject! if text.blank?

    kind = Extraction::Catalog.current.attributes[name]&.kind
    update!(status: "corrected", value: kind&.normalize(text) || text.strip, confidence: 1.0, reviewed_at: Time.current)
  end

  # A reviewed value is final; one a person threw out is written as missing.
  def to_finding
    Extraction::Finding.new(attribute: name, title: title, value: value, confidence: confidence, source: source,
                            rule: rule, raw: raw, alternatives: alternatives, evidence: evidence, note: note,
                            status: { "approved" => "accepted", "corrected" => "accepted", "rejected" => "missing" }.fetch(status, status))
  end
end
