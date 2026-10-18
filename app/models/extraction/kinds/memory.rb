module Extraction
  module Kinds
    # Storage and RAM are written the same way, so one reading of the text tells them apart:
    # "8/256 ГБ" names both, a word beside the number names one, a bare number is told by its size.
    class Memory < Base
      UNIT = "(гб|gb|тб|tb)".freeze
      RAM_SIZES = [ 1, 2, 3, 4, 6, 8, 12, 16, 18, 24, 32, 36, 48, 64 ].freeze
      STORAGE_SIZES = [ 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096 ].freeze
      STORAGE_RANGE = (4..16_384)

      # Excluding a preceding letter prevents a model suffix such as "A9+ 6/128"
      # from consuming "9+ 6" and hiding the real memory pair that follows.
      COMBO = %r{(?<![\p{L}\d.,])(\d{1,2})\s*(?:гб|gb)?\s*[/+]\s*(\d{1,4})\s*#{UNIT}?(?![\p{L}\p{N}])}i
      # The word after the number is tried before the word in front of it: in "6GB RAM 64GB storage"
      # the 64 belongs to what follows it.
      RAM = [
        /(?<![\d.,])(\d{1,3})\s*#{UNIT}\s*(?:оперативн|озу|ram#{Text::AFTER}|ddr)/i,
        /#{Text::BEFORE}(?:оперативн\p{L}*(?:\s+памят\p{L}*)?|озу|ram)[^\d\n]{0,15}?(\d{1,3})\s*#{UNIT}/i
      ].freeze
      STORAGE = [
        /(?<![\d.,])(\d{1,4})\s*#{UNIT}\s*(?:ssd|hdd|emmc|rom#{Text::AFTER}|storage|встроенн|накопител|памят)/i,
        /#{Text::BEFORE}(?:встроенн\p{L}*(?:\s+памят\p{L}*)?|накопител\p{L}*|ssd|hdd|emmc|rom|storage|памят\p{L}*)[^\d\n]{0,15}?(\d{1,4})\s*#{UNIT}/i
      ].freeze
      BARE = /(?<![\d.,])(\d{1,4})\s*#{UNIT}#{Text::AFTER}/i
      WHOLE = /(\d{1,5})\s*(гб|gb|тб|tb)?/i

      # "16 ГБ RAM (8+8)": 8 ГБ are in the phone, 8 more are borrowed from storage.
      VIRTUAL = /\(\s*(\d{1,2})\s*(?:гб|gb)?\s*\+\s*(\d{1,2})\s*(?:гб|gb)?\s*\)/i

      def scan(text, category:, source:)
        found = readings(text).filter_map { |role, size, raw, rule| Match.new(write(size), raw, rule) if role == self.role }
        (found + virtual(text, found)).uniq(&:value)
      end

      def normalize(raw, category: nil)
        # "4 МБ" of a push-button phone is not 4 ГБ: megabytes and kilobytes are not read as gigabytes.
        return if raw.to_s.match?(/\d\s*(?:мб|mb|кб|kb)#{Text::AFTER}/io)

        match = raw.to_s.match(WHOLE) or return
        size = gigabytes(match[1], match[2])
        write(size) if role == "ram" ? RAM_SIZES.include?(size) : STORAGE_RANGE.cover?(size)
      end

      def hint = "a number and a unit, e.g. \"256 ГБ\" or \"1 ТБ\""

      def role = options.fetch("role")

      private

      # The physical part as a reading of its own, so that the two disagree and a person decides.
      def virtual(text, found)
        return [] unless role == "ram" && (split = text.match(VIRTUAL))

        physical, borrowed = split.captures.map(&:to_i)
        total = write(physical + borrowed)
        found.any? { |match| match.value == total } ? [ Match.new(write(physical), split[0], "virtual_split") ] : []
      end

      # Each pattern takes what it read out of the text, so a weaker one does not read it again.
      def readings(text)
        rest = text.dup
        found = []

        take(rest, COMBO, found) do |match|
          ram, storage = match[1].to_i, gigabytes(match[2], match[3])
          next [] unless RAM_SIZES.include?(ram) && STORAGE_SIZES.include?(storage) && storage > ram

          rule = match[3] ? "combo" : "combo_unitless"
          [ [ "ram", ram, rule ], [ "storage", storage, rule ] ]
        end

        RAM.zip(STORAGE).each do |ram, storage|
          take(rest, ram, found) { |match| sized("ram", match, RAM_SIZES, "context") }
          take(rest, storage, found) { |match| sized("storage", match, STORAGE_RANGE, "context") }
        end

        take(rest, BARE, found) do |match|
          size = gigabytes(match[1], match[2])
          size >= 32 ? sized("storage", match, STORAGE_SIZES, "bare") : sized("ram", match, RAM_SIZES, "bare")
        end

        found
      end

      def take(rest, pattern, found)
        rest.gsub!(pattern) do
          match = Regexp.last_match
          read = yield(match)
          next match[0] if read.empty?

          read.each { |role, size, rule| found << [ role, size, match[0], rule ] }
          " " * match[0].length
        end
      end

      def sized(role, match, allowed, rule)
        size = gigabytes(match[1], match[2])
        allowed.include?(size) ? [ [ role, size, rule ] ] : []
      end

      def gigabytes(number, unit) = unit.to_s.match?(/\A(тб|tb)\z/i) ? number.to_i * 1024 : number.to_i

      # Terabytes only where the format has a way to write them; otherwise 1 ТБ is 1024.
      def write(size)
        terabytes = style["tb_suffix"]
        terabytes && size >= 1024 && (size % 1024).zero? ? "#{size / 1024}#{terabytes}" : "#{size}#{style['suffix']}"
      end
    end
  end
end
