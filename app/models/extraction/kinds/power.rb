module Extraction
  module Kinds
    # The product's electrical consumption, rather than its audio or charging output.
    class Power < Quantity
      CONTEXT = /(?<consumption>потребля\p{L}*|потреблен\p{L}*|мощност\p{L}*\s+(?:мотор\p{L}*|двигател\p{L}*))|(?<output>динамик\p{L}*|колонк\p{L}*|акустик\p{L}*|звук\p{L}*|аудио\p{L}*|всасыван\p{L}*|power\s*delivery|(?<!\p{L})pd(?!\p{L})|usb(?:[\s-]*[cс])?|type[\s-]*[cс]|зарядк\p{L}*)/i

      private

      def relevant?(text, match, _category)
        return false if text[match.end(:unit), 12].to_s.match?(/\A\s*(?:[·⋅∙•*]\s*)?(?:ч|h)(?!\p{L})/i)

        before = text[[ match.begin(0) - 90, 0 ].max...match.begin(0)].to_s.split(/[;.!?\n]/).last.to_s
        return true if before.match?(/(?:\A|,)\s*мощность\s*[:=—-]?\s*\z/i)

        context = before.to_enum(:scan, CONTEXT).map { Regexp.last_match }.last
        !context || !context[:output]
      end
    end
  end
end
