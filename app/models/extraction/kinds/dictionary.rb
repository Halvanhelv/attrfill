module Extraction
  module Kinds
    # A value from a closed list: the first one mentioned is the product's own.
    class Dictionary < Base
      # A list this short is given to the model whole.
      LISTED_IN_HINT = 30

      def scan(text, category:, source:)
        canonical, raw, position = dictionary.first(text)
        canonical ? [ Match.new(canonical, raw, rule_at(text, position, "dictionary")) ] : []
      end

      def normalize(raw, category: nil) = dictionary.normalize(raw)

      def open? = true

      def hint
        values = dictionary.canonicals
        "one of: #{values.join(', ')}" if values.size <= LISTED_IN_HINT
      end

      def dictionary = Extraction::Dictionary[options.fetch("dictionary")]

      private

      def rule_at(_text, _position, rule) = rule
    end
  end
end
