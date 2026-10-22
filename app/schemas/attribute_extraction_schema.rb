# One entry per attribute asked for; value and quote are null when the card does not say.
class AttributeExtractionSchema < Schematist::Schema
  array :attributes, description: "One item for each requested attribute" do
    object do
      string :name, description: "The attribute name, copied from the request"
      optional :value, description: "The value in the requested format, or null if the card does not give it" do
        string
      end
      optional :quote, description: "The verbatim fragment of the card the value was taken from, or null" do
        string
      end
    end
  end
end
