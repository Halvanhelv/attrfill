module Extraction
  module Kinds
    class Battery < Base
      RANGE = [ 300, 40_000 ].freeze
      UNIT = '(?:[мm][аa][·∙•*\s]?[чh])'.freeze
      # "5000 мА∙ч", or the unit named before the number: "Емкость аккумулятора (мАч): 6000".
      WITH_UNIT = /(?<![\p{L}\p{N}.,])(\d{1,2}[\s.]?\d{3}|\d{3,5})\s*#{UNIT}|\(#{UNIT}[^()]{0,40}\)\s*[:=\-–—]?\s*(\d{1,2}[\s.]?\d{3}|\d{3,5})(?!\d)/i
      WHOLE = /(\d{1,2}[\s.]?\d{3}|\d{3,5})/

      def scan(text, category:, source:)
        text.scan(WITH_UNIT).filter_map { |numbers| (number = numbers.compact.first) && (value = write(number, category)) && Match.new(value, number, "unit") }
            .uniq(&:value)
      end

      def normalize(raw, category: nil)
        number = raw.to_s[WHOLE, 1]
        number && write(number, category)
      end

      def hint = "a number, e.g. \"#{Format.write(5000, style)}\""

      private

      # "5 000" is five thousand; in "Watch 4 300 мАч" the 4 is the model's, which the category's range tells.
      def write(number, category)
        range = range_for(category)
        capacity = [ number.gsub(/\D/, "").to_i, number[/\d{3,}\z/].to_i ].find { |reading| range.cover?(reading) }

        Format.write(capacity, style) if capacity
      end

      def range_for(category)
        low, high = options.dig("ranges", category&.name) || RANGE
        (low..high)
      end
    end
  end
end
