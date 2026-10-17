module Extraction
  module Text
    BEFORE = '(?<![\p{L}\p{N}])'.freeze
    AFTER = '(?![\p{L}\p{N}])'.freeze

    TAG = %r{</?[a-zA-Z][^<>]{0,300}>}

    module_function

    # Case is kept: a model name and a processor are returned as they were written.
    def clean(value)
      text = value.to_s
      text = text.dup.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::BINARY
      text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: " ") unless text.encoding == Encoding::UTF_8
      text = text.scrub(" ") unless text.valid_encoding?
      text = CGI.unescapeHTML(text.gsub(TAG, " ").gsub(/&nbsp;/i, " ")) if text.match?(/[<&]/)

      text.unicode_normalize(:nfkc).tr("ёЁ", "еЕ").gsub(/[[:space:]]+/, " ").strip
    rescue ArgumentError, Encoding::CompatibilityError
      value.to_s.b.force_encoding(Encoding::UTF_8).scrub(" ").gsub(/[[:space:]]+/, " ").strip
    end

    def key(value) = clean(value).downcase

    # A pattern that only matches whole words, Cyrillic included (\b does not know them).
    def word(source) = /#{BEFORE}(?:#{source})#{AFTER}/i

    # A title that starts with an accessory ("Чехол на Samsung Galaxy S24", "Защитное стекло iPhone 15", "Пульт к
    # телевизору LG"): the device named after it is the one the accessory fits. Up to two adjectives may come first.
    ACCESSORY = /\A\s*(?:[\p{L}-]+(?:ое|ая|ый|ий|ой|ые|ие|яя)\s+){0,2}(?:чех(?:ол|лы|ла|лом)(?:-книжка)?|стекл[оа]|пл[её]нк[аи]|ремеш(?:ок|ки)|бампер|накладк[аи]|кабель|пульт|подставк[аи]|кронштейн|держател[ьи]|крепление|переходник|адаптер|стилус|наклейк[аи]|зарядное\s+устройство|аккумулятор\s+для|батаре[яи]\s+для)(?![\p{L}\p{N}])/i

    def accessory?(text) = text.to_s.match?(ACCESSORY)

    GIFT = /\s\+\s*(?=\p{L})[^+]*?(?:в\s+подарок|подарок|в\s+комплекте)/i

    # "Смартфон … 4/128 ГБ + Power Bank 10000 мАч в подарок" → "Смартфон … 4/128 ГБ": the gift is not the product.
    def without_gift(text)
      found = text.to_s.match(GIFT)
      found ? text[0...found.begin(0)] : text
    end

    # "чехол для смартфона Example": what follows names the device the product fits, not the product.
    def after_for?(text, position)
      prefix = text[0...position]
      # "Чехол на Samsung …", "Пульт к телевизору LG", "Подставка под монитор Samsung": in an accessory, as "для".
      return true if accessory?(text) && prefix.match?(/#{BEFORE}(?:на|к|ко|под)\s+(?:[\p{L}\p{N}-]+\s+){0,4}\z/io)
      # "Ноутбук для работы ASUS" names this product, not a compatible device.
      return false if prefix.match?(/#{BEFORE}(?:для|for)\s+(?:работы|учебы|учёбы|игр|детей|дома|офиса|work|gaming|kids|sale)#{AFTER}(?:\s+[\p{L}\p{N}-]+){0,4}\s+\z/io)

      # "Смартфон Oukitel C36 как Samsung": a brand compared with is not the product's own either.
      return true if prefix.match?(/#{BEFORE}(?:как|аналог|копия|вместо|like|replica)\s+\z/io)

      prefix.match?(/#{BEFORE}(?:для|for|compatible\s+with|совместим\p{L}*\s+с)\s+(?:[\p{L}\p{N}-]+\s+){0,4}\z/io)
    end

    def only_compatibility_mentions?(text, value)
      text = key(text)
      value = key(value)
      return false if value.blank?

      positions = text.to_enum(:scan, word(Regexp.escape(value))).map { Regexp.last_match.begin(0) }
      positions.any? && positions.all? { |position| after_for?(text, position) }
    end

    def number(value) = Float(value.to_s.tr(",", "."), exception: false)

    # 6.70 → "6.7", 55.0 → "55"
    def trim(number) = number.round(2).to_s.sub(/\.0+\z/, "").sub(/(\.\d*?)0+\z/, '\1')
  end
end
