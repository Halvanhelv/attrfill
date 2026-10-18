module Extraction
  module Kinds
    # A value recognised by its shape, listed as patterns in the catalog (a processor name).
    class Pattern < Base
      def scan(text, category:, source:)
        raw = first(text)
        return [ Match.new(written(raw), raw, "pattern") ] if raw

        families = family_patterns.flat_map do |pattern|
          text.to_enum(:scan, pattern).filter_map do
            raw = Regexp.last_match[0]
            name = family(raw)
            [ name, raw ] if name && !name.start_with?("Apple M")
          end
        end.uniq(&:first)
        families.one? ? [ Match.new(*families.first, "family") ] : []
      end

      def normalize(raw, category: nil) = first(Text.clean(raw))&.then { |found| written(found) }

      def open? = true

      # "Intel Core i7" is not wrong about an "Intel Core i7-1265U": a family matches its members.
      def same?(one, other)
        return true if super || (chip(one) == chip(other) && chip(one).present?)

        families = [ family(one), family(other) ]
        families.all? && families.uniq.size == 1 && [ one, other ].any? { |value| family(value).casecmp?(value.to_s.strip) }
      end

      # "Intel Core i7-1265U" → "Intel Core i7", by the catalog's families; nil when none fits.
      def family(value)
        Array(options["families"]).each do |source, template|
          match = value.to_s.match(Text.word(source))
          return template.gsub(/\\(\d)/) { match[Regexp.last_match(1).to_i].to_s.gsub(/\p{L}+/, &:capitalize) }.squish if match
        end
        nil
      end

      private

      # "Intel Core i5 12450H" and "Core i5-12450H" are one processor: no maker, no spaces or dashes.
      def chip(value) = value.to_s.downcase.gsub(/\b(?:intel|amd|apple|qualcomm|mediatek)\b|[^\p{L}\p{N}]/, "")

      def written(value) = (style["granularity"] == "family" && family(value)) || value

      def first(text)
        patterns.filter_map { |pattern| text.match(pattern) }.min_by { |match| match.begin(0) }&.then { |match| match[0].squish }
      end

      def patterns = @patterns ||= Array(options["patterns"]).map { |source| Text.word(source) }

      def family_patterns = @family_patterns ||= Array(options["families"]).map { |source, _| Text.word(source) }
    end
  end
end
