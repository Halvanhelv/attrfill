# POST /api/extraction — one card ({title, description, attributes, category}) or many ({cards: [...]}).
class Api::ExtractionsController < ActionController::API
  MAX_CARDS = 500
  FIELDS = %w[id title description category].freeze

  rescue_from ActionDispatch::Http::Parameters::ParseError do
    render json: { error: "The request body is not valid JSON" }, status: :bad_request
  end

  def create
    if params.key?(:cards) && (!params[:cards].is_a?(Array) || params[:cards].size > MAX_CARDS)
      return render json: { error: "cards must be an array of at most #{MAX_CARDS} cards" }, status: :unprocessable_entity
    end
    cards = params[:cards].is_a?(Array) ? params[:cards] : [ params ]
    unless cards.all? { |card| card.is_a?(Hash) || card.is_a?(ActionController::Parameters) }
      return render json: { error: "Each card must be an object" }, status: :unprocessable_entity
    end
    items = cards.map { |card| Item.new(build(card)) }
    results = Extraction::Runner.new.each(items).map { |_, result| present(result) }

    render json: params[:cards].is_a?(Array) ? { cards: results } : results.first
  end

  private

  Item = Data.define(:card)

  def build(card)
    card = card.respond_to?(:to_unsafe_h) ? card.to_unsafe_h : card.to_h
    seller = card["seller_attributes"] || card["attributes"]

    Extraction::Card.build(**card.slice(*FIELDS).symbolize_keys, seller_attributes: seller)
  end

  def present(result)
    { id: result.card.id, category: result.category.name, acceptance_mode: Extraction::Acceptance.mode,
      acceptance_policy: Extraction::Acceptance.policy_version,
      attributes: result.findings.map { |finding|
        finding.to_h.slice(:attribute, :title, :value, :confidence, :status, :source, :raw, :rule, :alternatives)
               .merge(needs_review: !finding.accepted?)
      } }
  end
end
