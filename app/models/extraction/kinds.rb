module Extraction
  # How a kind of attribute is found in text and brought to one way of writing it.
  module Kinds
    Match = Data.define(:value, :raw, :rule)

    class Base
      attr_reader :attribute

      def initialize(attribute)
        @attribute = attribute
      end

      # Readings found in free text.
      def scan(_text, category:, source:) = []

      # A value the seller gave as a whole, or nil when it cannot be read.
      def normalize(_raw, category: nil) = nil

      # Whether a seller's value that cannot be normalized is kept as written.
      def open? = false

      def same?(one, other) = one.to_s.casecmp?(other.to_s)

      # Told to the model so its answer comes in the same form.
      def hint = nil

      private

      def options = attribute.options

      def style = Format.of(attribute)
    end
  end
end
