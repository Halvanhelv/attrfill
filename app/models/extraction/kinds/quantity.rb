module Extraction
  module Kinds
    # Any number with a unit: the catalog names the units (and what each is worth), the range and how it is written.
    #   units: [гц, hz]            or   units: { кг: 1, kg: 1, г: 0.001 }
    class Quantity < Base
      NUMBER = '(\d{1,3}(?:[\s.]\d{3})+|\d{1,7}(?:[.,]\d{1,2})?)'.freeze

      def scan(text, category:, source:)
        text.to_enum(:scan, pattern).filter_map do
          match = Regexp.last_match
          next unless relevant?(text, match, category)

          value = write(match[:number], match[:unit])
          Match.new(value, match[0], "unit") if value
        end.uniq(&:value)
      end

      # A seller's bare number is taken in the first unit listed.
      def normalize(raw, category: nil)
        match = raw.to_s.match(pattern)
        return write(match[:number], match[:unit]) if match

        number = raw.to_s[/#{NUMBER}/o, 1]
        number && write(number, nil)
      end

      def hint = "a number, e.g. \"#{Format.write(range.begin, style)}\""

      private

      def relevant?(_text, _match, _category) = true

      def write(number, unit)
        number = number.match?(/\d[\s.]\d{3}\b/) && !number.match?(/[.,]\d{1,2}\z/) ? number.gsub(/[\s.]/, "") : number
        amount = Text.number(number) or return
        amount *= units.fetch(unit.to_s.downcase, units.values.first)

        Format.write(amount, style) if range.cover?(amount)
      end

      # "393 л", or the unit named before the number as specification lists write it: "Общий объем (л) - 393".
      def pattern
        @pattern ||= begin
          unit = units.keys.sort_by { |name| -name.length }.map { |name| Regexp.escape(name) }.join("|")
          /(?<![\p{L}\p{N}.,])(?<number>#{NUMBER})\s*(?<unit>#{unit})#{Text::AFTER}|\((?<unit>#{unit})#{Text::AFTER}[^()]{0,40}\)\s*[:=\-–—]?\s*(?<number>#{NUMBER})(?![\p{N}])/i
        end
      end

      def units
        @units ||= begin
          listed = options.fetch("units")
          (listed.is_a?(Hash) ? listed : listed.to_h { |unit| [ unit, 1 ] }).transform_keys { |unit| unit.to_s.downcase }
        end
      end

      def range
        low, high = options["range"] || [ 0, 10_000_000 ]
        (low.to_f..high.to_f)
      end
    end
  end
end
