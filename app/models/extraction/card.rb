module Extraction
  # The text of one product card, cleaned once.
  Card = Data.define(:id, :title, :description, :seller_attributes, :category) do
    def self.build(id: nil, title: nil, description: nil, seller_attributes: nil, category: nil)
      new(id: id, title: Text.clean(title), description: Text.clean(description),
          seller_attributes: SellerAttributes.parse(seller_attributes), category: Text.clean(category).presence)
    end

    # Where a title's facts are looked for; a card without a title opens its description with them.
    def heading = title.presence || description[/\A[^.!?\n]{1,200}/].to_s

    def seller_text = seller_attributes.map { |key, value| "#{key}: #{value}" }.join("; ")

    # Everything a value may be quoted from.
    def text = [ title, description, seller_text ].compact_blank.join("\n")
  end
end
