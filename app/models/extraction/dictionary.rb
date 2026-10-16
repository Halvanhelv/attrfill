module Extraction
  # Canonical values and the ways each is written, from config/dictionaries. A learned file of the same name
  # under learned/ is merged in.
  class Dictionary
    ENDINGS = %w[ый ий ой ая яя ое ее ого его ому ему ую юю ые ие ом ем ым им ых их ыми ими].freeze

    FUZZY_MIN = 6

    def self.[](name)
      (@loaded ||= {})[name.to_s] ||= new(entries_for(name), names: names_for(name))
    end

    # How a labelled dataset writes a value this dictionary writes differently: { ours => theirs }.
    def self.names_for(name)
      path = Extraction.config_path("dictionaries", "learned", "#{name}.names.yml")
      path.exist? ? (YAML.load_file(path) || {}) : {}
    end

    def self.reset! = @loaded = nil

    def self.entries_for(name)
      [ "#{name}.yml", "learned/#{name}.yml" ].each_with_object({}) do |file, entries|
        path = Extraction.config_path("dictionaries", file)
        next unless path.exist?

        (YAML.load_file(path) || {}).each do |canonical, forms|
          forms = Array(forms)
          # Brands learned from labels are filtered for words that are not makers (Kinds::Brand.junk?).
          if name.to_s == "brands" && file.start_with?("learned/")
            next if Kinds::Brand.junk?(canonical)

            forms = forms.reject { |form| Kinds::Brand.junk?(form) }
          end
          (entries[canonical.to_s] ||= []).concat(forms)
        end
      end
    end

    attr_reader :pattern

    def initialize(entries, names: {})
      @names = names
      @own = entries.keys
      @exact = {}
      @stems = {}

      entries.each do |canonical, forms|
        [ canonical, *forms ].each do |form|
          form = Text.key(form)
          next if form.blank?

          form.end_with?("~") ? @stems[form.chomp("~")] ||= canonical : @exact[form] ||= canonical
        end
      end

      @pattern = build_pattern
    end

    def empty? = @exact.empty? && @stems.empty?

    # Every mention, in the order written: [canonical, as written, position].
    def scan(text)
      return [] if empty?

      text.to_enum(:scan, pattern).map do
        match = Regexp.last_match
        [ canonical(match[0]), match[0], match.begin(0) ]
      end
    end

    def first(text) = pattern && text.match(pattern)&.then { |match| [ canonical(match[0]), match[0], match.begin(0) ] }

    # The canonical value of a string that is one value, or of the first one mentioned in it.
    def normalize(raw)
      return if empty?

      canonical(raw) || first(Text.clean(raw))&.first
    end

    def canonicals = @own.map { |canonical| @names.fetch(canonical, canonical) }

    def canonical(form)
      form = Text.key(form)
      found = @exact[form] || @stems.find { |stem, _| form.start_with?(stem) && ENDINGS.include?(form.delete_prefix(stem)) }&.last
      found && @names.fetch(found, found)
    end

    # A long word one letter away from a known one: a typo. [canonical, as written, position]
    def fuzzy(text)
      text.to_enum(:scan, /[\p{L}\p{N}]{#{FUZZY_MIN},}/o).each do
        match = Regexp.last_match
        word = match[0].downcase
        close = fuzzy_forms.find { |form| form[0] == word[0] && typo?(form, word) }
        return [ canonical(close), match[0], match.begin(0) ] if close
      end

      nil
    end

    private

    # One letter added, dropped or changed, or two neighbours swapped.
    def typo?(form, word)
      return false if (form.length - word.length).abs > 1

      distance = DidYouMean::Levenshtein.distance(form, word)
      distance == 1 || (distance == 2 && form.chars.sort == word.chars.sort)
    end

    def fuzzy_forms = @fuzzy_forms ||= @exact.keys.select { |form| form.length >= FUZZY_MIN && form.match?(/\A[\p{L}\p{N}]+\z/) }

    # Longest first, so "dark blue" is not read as "blue".
    def build_pattern
      return if empty?

      exact = @exact.keys.map { |form| [ form.length, form[0], Regexp.escape(form[1..]).gsub('\ ', '\s+') ] }
      stems = @stems.keys.map { |stem| [ stem.length + 3, stem[0], "#{Regexp.escape(stem[1..])}(?:#{ENDINGS.join('|')})" ] }

      # Factor out the first character: a large learned dictionary should not
      # try thousands of unrelated alternatives at every character of a long
      # description. Keep longest-first order within each prefix.
      grouped = (exact + stems).sort_by { |length, _, _| -length }.group_by { |_, first, _| first }
      source = grouped.map do |first, entries|
        "#{Regexp.escape(first)}(?:#{entries.map(&:last).join('|')})"
      end.join("|")
      Text.word(source)
    end
  end
end
