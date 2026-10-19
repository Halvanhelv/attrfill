module Extraction
  module Kinds
    # A refrigerator's total: an explicit total wins; two named compartments may be added.
    class Volume < Quantity
      CONTEXT = /(?<total>(?:общ\p{L}*|суммарн\p{L}*)\s+(?:полезн\p{L}*\s+)?(?:об[ъь][её]м\p{L}*|вместимост\p{L}*))|(?<fresh>зон\p{L}*\s+свежест\p{L}*)|(?<freezer>морозильн\p{L}*(?:\s+(?:камер\p{L}*|отсек\p{L}*|отделени\p{L}*))?|морозилк\p{L}*)|(?<fridge>холодильн\p{L}*\s+(?:камер|отсек|отделени)\p{L}*)/i
      INCLUSION = /в\s+том\s+числе|из\s+них|из\s+которых|включа(?:я|ет|ют)/i
      BASIS = /(?<gross>полн\p{L}*|общ\p{L}*\s+об[ъь][её]м\p{L}*|брутто)|(?<net>полезн\p{L}*|нетто)/i

      def scan(text, category:, source:)
        readings = text.to_enum(:scan, pattern).filter_map do
          match = Regexp.last_match
          value = write(match[:number], match[:unit])
          [ Match.new(value, match[0], "unit"), role(text, match.begin(0)), match.begin(0)...match.end(0) ] if value
        end

        totals = readings.select { |_, role| role == "total" }.map(&:first)
        return totals.uniq(&:value) if totals.any?

        fridge, freezer = %w[fridge freezer].map do |role|
          readings.select { |_, found| found == role }.map(&:first).uniq(&:value)
        end
        if fridge.one? && freezer.one? && additive?(text)
          amount = [ fridge.first, freezer.first ].sum { |reading| Text.number(reading.value.to_s[/[\d.,]+/]) }
          value = write(amount.to_s, nil)
          if value
            spans = readings.select { |_, role| %w[fridge freezer].include?(role) }.map(&:last)
            raw = text[spans.map(&:begin).min...spans.map(&:end).max]
            derived = Match.new(value, raw, "component_sum")
            return ([ derived ] + readings.select { |_, role| role.nil? }.map(&:first)).uniq(&:value)
          end
        end

        readings.map(&:first).uniq(&:value)
      end

      private

      def role(text, position)
        context = before(text, position).to_enum(:scan, CONTEXT).map { Regexp.last_match }.last
        context&.named_captures&.find { |_, value| value }&.first
      end

      def additive?(text)
        # Inclusion can follow the number too. Prefer no sum over adding an already included compartment.
        return false if text.match?(INCLUSION)

        bases = text.to_enum(:scan, BASIS).filter_map do
          Regexp.last_match.named_captures.find { |_, value| value }&.first
        end
        bases.uniq.size <= 1
      end

      def before(text, position)
        text[[ position - 100, 0 ].max...position].to_s.split(/[;.!?\n]/).last.to_s
      end
    end
  end
end
