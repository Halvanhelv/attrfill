class CardsController < ApplicationController
  def new
    render locals: { categories: Extraction::Catalog.current.categories.values }
  end

  def create
    fields = card_params.to_h.symbolize_keys
    if fields.values_at(:title, :description, :seller_attributes).all?(&:blank?)
      return redirect_to new_card_path, alert: "Enter a title, a description or seller attributes: there is nothing to extract from an empty card."
    end

    redirect_to Card.extract!(**fields)
  end

  def show
    render locals: { card: Card.includes(:attribute_values).find(params[:id]) }
  end

  private

  def card_params = params.require(:card).permit(:title, :description, :seller_attributes, :category)
end
