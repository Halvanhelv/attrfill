module Extraction
  module Kinds
    # A screen resolution: a class from the dictionary ("Full HD", "4K UHD") or pixels written out ("2400x1080").
    # Pixels a class covers are written as that class; two values are one when they are the same pixels.
    class Resolution < Dictionary
      PIXELS = /(?<!\p{N})(\d{3,4})\s*[xх×*]\s*(\d{3,4})(?!\p{N})/i

      # Words before a class that speak of the content, the camera or the upscaler, not of this screen:
      # "улучшение HD-контента до 4K", "запись видео 4K", "поддержка 4K-сигнала".
      CONTENT = /(?:до|up\s+to|улучшен\p{L}*|апскейл\p{L}*|масштабир\p{L}*|upscal\p{L}*|контент\p{L}*|видео\p{L}*|запис\p{L}*|съ[её]мк\p{L}*|камер\p{L}*|hdmi|сигнал\p{L}*|источник\p{L}*|воспроизв\p{L}*|декодир\p{L}*)[^.;!?\n]{0,25}\z/i
      # Words before a class that name this screen: "Разрешение экрана Full HD".
      # "экрана форматом 16:9" names the shape, so the screen words count only right before the class.
      SCREEN = /(?:(?:разрешени\p{L}*|resolution)[^.;!?\n\d]{0,25}|(?:экран\p{L}*|диспле\p{L}*|матриц\p{L}*)\s*[:—–-]?\s*)\z/i

      def scan(text, category:, source:)
        match = pixel_match(text)
        return [ Match.new(write(match), match[0], "pixels") ] if match

        classes(text)
      end

      def normalize(raw, category: nil)
        match = pixel_match(raw.to_s)
        match ? write(match) : super
      end

      def same?(one, other)
        pair, pair_other = pixels(one), pixels(other)
        pair && pair_other ? pair == pair_other : super
      end

      private

      # VESA mounting patterns and cabinet dimensions also use AxB notation.
      # They must not hide the screen resolution later in the description.
      def pixel_match(text)
        text.to_enum(:scan, PIXELS).filter_map do
          match = Regexp.last_match
          next if match.captures.map(&:to_i).min < 480
          next if text[match.end(0)..].match?(/\A\s*(?:мм|mm|см|cm)#{Text::AFTER}/i)
          next if text[0...match.begin(0)].match?(/(?:vesa|креплен\p{L}*)\s*[:(—–-]?\s*\z/i)
          # "до 7680x4320": what a port or a decoder can take, not the panel.
          next if text[0...match.begin(0)].match?(/(?:до|up\s+to)\s*\z/i)

          match
        end.first
      end

      # The class named for the screen wins. Otherwise every class not spoken of as content is a reading of its own,
      # so that two of them disagree and go to a person; one only spoken of as content is a mere mention.
      def classes(text)
        found = dictionary.scan(text).map { |canonical, raw, position| [ canonical, raw, text[0...position] ] }
        named = found.find { |_, _, before| before.match?(SCREEN) }
        return [ Match.new(named[0], named[1], "dictionary") ] if named

        plain, content = found.partition { |_, _, before| !before.match?(CONTENT) }
        return plain.uniq(&:first).map { |canonical, raw, _| Match.new(canonical, raw, "dictionary") } if plain.any?

        content.uniq(&:first).map { |canonical, raw, _| Match.new(canonical, raw, "mention") }
      end

      def write(match)
        written = match.captures.map(&:to_i).sort.reverse.join("x")
        dictionary.canonical(written) || written
      end

      def pixels(value)
        match = value.to_s.match(PIXELS)
        match ? match.captures.map(&:to_i).sort : class_pixels[Text.key(value)]
      end

      # "Full HD" → [1080, 1920], under our name and under the name the labels use for it.
      def class_pixels
        @class_pixels ||= begin
          name = options.fetch("dictionary")
          renamed = Extraction::Dictionary.names_for(name)
          Extraction::Dictionary.entries_for(name).each_with_object({}) do |(canonical, forms), result|
            match = forms.lazy.map { |form| form.to_s.match(PIXELS) }.find(&:itself) or next
            [ canonical, renamed[canonical] ].compact.each { |label| result[Text.key(label)] = match.captures.map(&:to_i).sort }
          end
        end
      end
    end
  end
end
