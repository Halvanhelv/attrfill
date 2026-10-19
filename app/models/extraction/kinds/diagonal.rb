module Extraction
  module Kinds
    # A screen size in inches, kept only when it is a size a product of this category can have.
    class Diagonal < Base
      NUMBER = '(\d{1,3}(?:[.,]\d{1,2})?)'.freeze
      WITH_UNIT = /(?<![\d.,\/x×х])#{NUMBER}\s*(?:"|''|′′|″|”|“|['’′](?![\p{L}\p{N}])|дюйм\p{L}*|inch(?:es)?#{Text::AFTER})/i
      IN_CONTEXT = /#{Text::BEFORE}(?:диагонал\p{L}*|экран\p{L}*|диспле\p{L}*)[^\d\n]{0,20}?#{NUMBER}(?![\d.,]*\s*(?:гц|hz|мач|mah|гб|gb|мп|mp|нит|x|х|×|p#{Text::AFTER}))/i
      WHOLE = /#{NUMBER}/
      # "Телевизор TCL 50P7K", "Монитор Samsung S27D300GAI": the size opens a model code, or follows its letters.
      IN_CODE = /(?<![\p{L}\p{N}.,])(?:(?:\p{Lu}{1,4}-?){0,2}(\d{2})(?=\d{0,2}\p{Lu})|(\d{2})(?=\s+(?i:smart|q?led|oled|qned|uhd|4k)#{Text::AFTER}))/

      def scan(text, category:, source:)
        range = range_for(category)
        found = text.scan(WITH_UNIT).map { |(number)| [ number, "unit" ] } +
                text.scan(IN_CONTEXT).map { |(number)| [ number, "context" ] }
        found += text.scan(IN_CODE).map { |numbers| [ numbers.compact.first, "code" ] } if source == "title" && in_code?(category)

        found.filter_map { |number, rule| (value = write(number, range)) && Match.new(value, number, rule) }.uniq(&:value)
      end

      # The number with an inch mark first ("AMOLED 2.5D, 1.43\"" is 1.43"); centimetres and millimetres are not inches.
      def normalize(raw, category: nil)
        text = raw.to_s
        number = text[WITH_UNIT, 1]
        unless number
          return if text.match?(/\d\s*(?:см|cm|мм|mm)#{Text::AFTER}/io)

          number = text[WHOLE, 1]
        end
        number && write(number, range_for(category))
      end

      def hint = 'a number in inches, e.g. "6.7""'

      private

      def write(number, range)
        inches = Text.number(number)
        Format.write(inches, style) if inches && range.cover?(inches)
      end

      def in_code?(category) = Array(options["in_code"]).include?(category&.name)

      def range_for(category)
        low, high = options.dig("ranges", category&.name) || [ 1, 120 ]
        (low.to_f..high.to_f)
      end
    end
  end
end
