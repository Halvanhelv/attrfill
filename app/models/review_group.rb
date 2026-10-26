require "digest"

# Explicit human decisions for duplicate inputs, never propagation by value alone.
class ReviewGroup
  LIMIT = 100
  TTL = 15.minutes
  RESTORE = %w[value confidence status reviewed_at].freeze
  class Conflict < StandardError; end

  def self.key(value)
    card = value.card
    Digest::SHA256.hexdigest([ card.title, card.description, card.category, card.detected_category,
      card.seller_attributes.sort, value.name, value.value, value.raw, value.source,
      value.rule, value.confidence, value.alternatives ].to_json)
  end

  def self.fingerprint(value)
    Digest::SHA256.hexdigest([ key(value), value.attributes, value.updated_at&.iso8601(6) ].to_json)
  end

  def self.preview(seed)
    raise Conflict, "The value has already been reviewed. Refresh the queue." unless seed.review?

    # Bound both the query and the output. The preview's fixed ID list is the
    # entire scope of the later decision, even if new duplicates arrive.
    candidates = AttributeValue.waiting.joins(:card).includes(:card)
      .where(name: seed.name, value: seed.value, cards: { title: seed.card.title,
        description: seed.card.description, detected_category: seed.card.detected_category })
      .where.not(id: seed.id).reorder(:id).limit(LIMIT * 5)
    expected_key = key(seed)
    # The value the person opened the group from is always in it, whatever the order of the others.
    values = [ seed, *candidates.select { |value| key(value) == expected_key } ].first(LIMIT)
    { values: values, token: sign(values.to_h { |value| [ value.id.to_s, fingerprint(value) ] }, "preview") }
  end

  def self.apply(token, decision:, replacement: nil)
    raise Conflict, "Choose to approve or correct." unless %w[approve correct].include?(decision)
    raise Conflict, "Enter the correct value." if decision == "correct" && replacement.blank?

    expected = verify(token, "preview")
    snapshots = {}
    after = {}
    AttributeValue.transaction do
      values = locked(expected)
      raise Conflict, "Some values have already been reviewed. Refresh the group." unless values.all?(&:review?)
      values.each do |value|
        snapshots[value.id.to_s] = value.attributes.slice(*RESTORE)
        decision == "approve" ? value.approve! : value.correct!(replacement)
        after[value.id.to_s] = fingerprint(value.reload)
      end
    end
    { count: after.size, undo_token: sign({ "expected" => after, "before" => snapshots }, "undo") }
  end

  def self.undo(token)
    receipt = verify(token, "undo")
    AttributeValue.transaction do
      values = locked(receipt.fetch("expected"))
      values.each { |value| value.update!(receipt.fetch("before").fetch(value.id.to_s).slice(*RESTORE)) }
      values.size
    end
  end

  def self.locked(expected)
    raise Conflict, "Invalid group." unless expected.is_a?(Hash) && expected.size.between?(2, LIMIT)
    values = AttributeValue.where(id: expected.keys).order(:id).lock.includes(:card).to_a
    unless values.size == expected.size && values.all? { |value| fingerprint(value) == expected[value.id.to_s] }
      raise Conflict, "The cards changed after you viewed them. Open the group again; other reviewers' decisions are kept."
    end
    values
  end

  def self.sign(data, purpose)
    Rails.application.message_verifier("review-group").generate(data, purpose: purpose, expires_in: TTL)
  end

  def self.verify(token, purpose)
    Rails.application.message_verifier("review-group").verify(token, purpose: purpose)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    raise Conflict, "The group link is invalid or has expired. Open the group again."
  end
  private_class_method :locked, :sign, :verify
end
