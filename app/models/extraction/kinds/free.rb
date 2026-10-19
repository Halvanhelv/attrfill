module Extraction
  module Kinds
    # An attribute with no rule of its own (kind: free): taken from the seller's field as written, or asked of the model.
    # The quickest way to add a field a dataset turns out to require.
    class Free < Base
      def normalize(raw, category: nil) = Text.clean(raw).presence

      def hint = options["hint"]
    end
  end
end
