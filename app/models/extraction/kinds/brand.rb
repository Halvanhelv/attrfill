require "strscan"

module Extraction
  module Kinds
    # A brand by its name, by a product line that belongs to it, by a name one letter off,
    # or, when no dictionary knows it, by where brands stand in a title.
    class Brand < Dictionary
      # "Смартфон Kvazar K7": a capitalised Latin word right after the Russian words that name the product,
      # past the Latin words that only describe it ("Наушники True Wireless Kvazar").
      PREFIX = /\A(?:[А-Яа-я]+[\s-]+){1,3}/
      WORD = /[A-Za-z][A-Za-z0-9&]{1,19}(?![\p{L}\p{N}])/

      # Capitalised Latin words that stand in that place without being anyone's name.
      NOT_BRANDS = %w[usb hdmi led lcd oled qled smart tv ssd hdd type wifi wi bluetooth full ultra hd pro max mini nfc gps lte sim dual
                      android windows ios mac pc ip gb tb hz true wireless tws side by].to_set.freeze

      # Not names of makers, though sellers put them in the brand field often enough to be learned from the labels:
      # "Sim", "Wireless", "Gb", "2K", "HOME", colours, "#N/A". A learned brand like these took the place of the real
      # one in titles ("Мобильный телефон 2 SIM Nokia 105" → "Sim") and was accepted.
      JUNK = %w[home orange green red sim mi mb kb gb tb max new plus edition series original].to_set.freeze

      def self.junk?(form)
        key = form.to_s.downcase.strip
        return true if key.scan(/\p{L}/).size < 2 || key.match?(/\A\d+\s*\p{L}{1,3}\z/) || key.match?(%r{[#/@%=<>]})

        NOT_BRANDS.include?(key) || JUNK.include?(key) || Extraction::Dictionary["colors"].canonical(key).present?
      end

      def self.guess(title)
        scanner = StringScanner.new(title)
        return unless scanner.skip(PREFIX)

        while (word = scanner.scan(WORD))
          return word.match?(/\A[A-Z]/) && [ word, word, scanner.charpos - word.size ] unless NOT_BRANDS.include?(word.downcase)

          scanner.skip(/[\s-]+/)
        end
      end

      # A description names other brands too (a processor, a compatible device), so there a brand is only a mention.
      def scan(text, category:, source:)
        found = super
        found = line(text) if found.empty?
        found = found.reject { |match| match.rule == "compatibility" }
        return found.map { |match| match.with(rule: "mention") } unless source == "title"

        found.presence || typo(text) || placed(text) || []
      end

      private

      def line(text)
        brand, raw, position = lines.first(text)
        brand ? [ Match.new(brand, raw, rule_at(text, position, "product_line")) ] : []
      end

      def typo(text)
        brand, raw, position = dictionary.fuzzy(text)
        [ Match.new(brand, raw, "fuzzy") ] if brand && !Text.after_for?(text, position)
      end

      def placed(text)
        brand, raw, position = self.class.guess(text)
        [ Match.new(brand, raw, "position") ] if brand && !Text.after_for?(text, position)
      end

      # A brand named after "для" is the one the product fits, not its own: it is not read at all.
      def rule_at(text, position, rule) = Text.after_for?(text, position) ? "compatibility" : rule

      def lines = Extraction::Dictionary["brand_lines"]
    end
  end
end
