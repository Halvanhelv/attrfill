module Extraction
  module Kinds
    # A model has no list to check against: in a title it is what follows the brand,
    # up to the first thing that is a characteristic rather than a name.
    class Model < Base
      MAX_WORDS = 6
      EDGES = /\A[\s\-–—:.,\/]+|[\s\-–—:.,\/]+\z/

      def scan(text, category:, source:)
        return [] unless source == "title"

        start, named_at, guessed = name_start(text)
        return [] unless start

        name = text[start..].split(stop, 2).first.to_s.split.first(MAX_WORDS).join(" ").gsub(EDGES, "")
        return [] unless name.match?(/[\p{L}\p{N}]{2}/)

        return [] if Text.after_for?(text, named_at)

        [ Match.new(name, name, guessed ? "after_guess" : name.match?(/\d/) ? "after_brand" : "after_brand_plain") ]
      end

      # Sellers often repeat the brand in the model field.
      def normalize(raw, category: nil)
        name = Text.clean(raw)
        _, brand, position = brands.first(name)
        name = name[brand.length..] if position&.zero?
        name.gsub(EDGES, "").presence
      end

      # "Galaxy S24 Ultra" and "Galaxy S24 Ultra 5G" are one model said two ways.
      def same?(one, other)
        short, long = [ bare(one), bare(other) ].sort_by(&:length)
        short.present? && long.include?(short)
      end

      def hint = "the model name without the brand, as written in the card"

      private

      # After the brand's name; a product line is already part of the model's.
      def name_start(text)
        _, raw, position = brands.first(text)
        return [ position + raw.length, position ] if position

        position = lines.first(text)&.last
        return [ position, position ] if position

        _, raw, position = brands.fuzzy(text) || Brand.guess(text)
        [ position + raw.length, position, true ] if position
      end

      def bare(name) = name.to_s.downcase.gsub(/[^\p{L}\p{N}]/, "")

      def stop
        @stop ||= Regexp.union([
          /[,(\[|;]/, /\s[-–—]\s/,
          %r{#{Text::BEFORE}\d{1,2}\s*[/+]\s*\d{1,4}},
          /#{Text::BEFORE}\d{1,4}\s*(?:гб|gb|тб|tb)(?!\p{L})/i,
          /#{Text::BEFORE}\d{1,3}(?:[.,]\d{1,2})?\s*(?:"|'|’|′|″|”|дюйм|inch)/i,
          /#{Text::BEFORE}(?:core\s+)?i[3579]-?\d{4,5}/i,
          # A lowercase Russian word is a description, not part of a name.
          /#{Text::BEFORE}[а-я]{3,}/,
          /#{Text::BEFORE}\d{3,5}\s*(?:мач|mah)/i,
          Extraction::Dictionary["colors"].pattern, Extraction::Dictionary["resolutions"].pattern,
          /#{Text::BEFORE}\d{1,5}(?:[.,]\d{1,2})?\s*(?:гц|hz|мп|mp|к?вт|k?w|кг|kg|л|мм|mm|см|об)(?!\p{L})/i,
          Text.word('смартфон|телефон|ноутбук|планшет|телевизор|цвет\p{L}*|dual\s*sim|nfc|lte|wi-?fi|ssd|hdd|для|с|и|with|for|and|smart\s*tv')
        ].compact)
      end

      def brands = Extraction::Dictionary["brands"]
      def lines = Extraction::Dictionary["brand_lines"]
    end
  end
end
