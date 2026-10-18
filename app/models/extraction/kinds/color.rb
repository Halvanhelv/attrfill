module Extraction
  module Kinds
    # Unlike a brand dictionary, color must preserve competing mentions. A color
    # elsewhere in a long description may belong to packaging, an image or light.
    class Color < Dictionary
      CONTEXT = /(?:цвет\p{L}*|расцветк\p{L}*|корпус\p{L}*)[^.!?;]{0,24}\z/i
      AFTER_CONTEXT = /\A[\s,\-]*(?:цвет\p{L}*|расцветк\p{L}*|корпус\p{L}*)/i
      NEGATED = /(?:\bnot|#{Text::BEFORE}не)\s+\z/i
      ACCESSORY = /\A\s+(?:чехол|кабел|упаковк|подсветк)\p{L}*/i

      def scan(text, category:, source:)
        matches = dictionary.scan(text).filter_map do |value, raw, position|
          next if negated?(text, position: position)

          Match.new(value, raw, evidence_rule(text, position: position, length: raw.length, source: source))
        end.uniq { |match| [ match.value, match.rule ] }
        source == "description" ? matches.first(1) : matches
      end

      def negated?(text, position:) = text[0...position].match?(NEGATED)

      def evidence_rule(text, position:, length:, source:)
        after = text[(position + length)..]
        return "mention" if after.match?(ACCESSORY)
        return "dictionary" unless source == "description"

        text[0...position].match?(CONTEXT) || after.match?(AFTER_CONTEXT) ? "dictionary" : "mention"
      end
    end
  end
end
