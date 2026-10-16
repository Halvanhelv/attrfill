module Extraction
  # What is extracted for which category, read from config/catalog.yml.
  class Catalog
    Category = Data.define(:name, :title, :label, :keywords, :attributes)

    class Attribute
      attr_reader :name, :title, :label, :seller_keys, :threshold, :options

      # title is the attribute's name as Russian cards and datasets write it (it is matched against them);
      # label is what the interface shows, falling back to the title when the catalog gives none.
      def initialize(name, definition, defaults)
        @name = name
        @title = definition["title"] || name
        @label = definition["label"] || Catalog.label(@title)
        @seller_keys = Array(definition["seller_keys"]).map { |key| Text.key(key) }
        @threshold = (definition["threshold"] || defaults["threshold"] || 0.8).to_f
        @options = definition
      end

      def kind = @kind ||= Kinds.const_get(options.fetch("kind").camelize).new(self)

      # Whether asking a model about this attribute can pay: the card says something about it (its name, a seller's
      # key for it, its unit). Names (ask_model: always) are worth asking about whatever the card says.
      def worth_asking?(text)
        options["ask_model"] == "always" || cues.match?(Text.key(text))
      end

      private

      def cues
        @cues ||= begin
          units = (options["units"].is_a?(Hash) ? options["units"].keys : Array(options["units"])) + Array(options["cues"])
          words = [ title, *seller_keys ].flat_map { |words| Text.key(words).split }
          stems = words.map { |word| word.gsub(/[^\p{L}\p{N}]/, "")[0, 6] }.select { |stem| stem.length >= 3 }.uniq
          # A unit stands right after its number ("300l"), a word on its own.
          units = units.map { |unit| "(?<!\\p{L})#{Regexp.escape(Text.key(unit))}(?!\\p{L})" }
          /#{Text::BEFORE}(?:#{stems.map { |stem| Regexp.escape(stem) }.join("|")})|#{units.join("|").presence || "(?!)"}/
        end
      end
    end

    CATEGORY_KEYS = [ "категория", "тип", "тип товара", "вид товара", "category", "type" ].freeze

    def self.current = @current ||= new(config)

    # config/catalog.yml, with the categories and attributes generated from a dataset (catalog.*.yml) it does not name.
    def self.config
      Dir[Extraction.config_path("catalog.*.yml")].sort.each_with_object(YAML.load_file(Extraction.config_path("catalog.yml"))) do |path, config|
        generated = YAML.load_file(path) || {}
        %w[categories attributes].each { |part| config[part] = (generated[part] || {}).merge(config[part]) }
      end
    end
    def self.reset!
      @current = nil
      @labels = nil
    end

    attr_reader :attributes, :categories

    # The English interface label of a Russian title from a generated catalog (config/catalog.labels.yml), or the title.
    def self.label(title)
      @labels ||= begin
        path = Extraction.config_path("catalog.labels.yml")
        path.exist? ? (YAML.load_file(path) || {}) : {}
      end
      @labels.fetch(title.to_s.gsub(/[[:space:]]+/, " ").strip, title)
    end

    def initialize(config)
      defaults = config["defaults"] || {}
      @attributes = config.fetch("attributes").to_h { |name, definition| [ name, Attribute.new(name, definition, defaults) ] }
      @categories = config.fetch("categories").to_h do |name, definition|
        title = definition["title"] || name
        [ name, Category.new(name: name, title: title, label: definition["label"] || Catalog.label(title), keywords: Array(definition["keywords"]),
                             attributes: definition.fetch("attributes").map { |attribute| @attributes.fetch(attribute) }) ]
      end
    end

    def generic = categories.fetch("generic")

    # The category the dataset names, else the one the title names first, else what the seller calls the product.
    # An accessory named first ("a case for Samsung Galaxy S24") is not the device it fits: it gets no device's fields.
    def detect(card)
      named(card.category) || (generic if Text.accessory?(card.heading)) || mentioned_first(card.heading) ||
        named(card.seller_attributes.values_at(*CATEGORY_KEYS).compact.first) || generic
    end

    # A generic product may mention only the device it fits ("case for Samsung Galaxy S24"). Rules already
    # ignore names after "for"; learned layers must observe the same boundary instead of restoring them.
    def compatibility_only?(card)
      matches = keyword_patterns.filter_map { |_, pattern| card.heading.match(pattern) }
      matches.any? && matches.all? { |match| Text.after_for?(card.heading, match.begin(0)) }
    end

    private

    def named(text)
      return if text.blank?

      key = Text.key(text)
      categories.values.find { |category| key == category.name || key == Text.key(category.title) } || mentioned_first(text)
    end

    # The earliest keyword wins; of two starting at one place the longer ("galaxy tab" over "galaxy").
    def mentioned_first(text)
      keyword_patterns.filter_map do |category, pattern|
        match = text.match(pattern)
        [ [ match.begin(0), -match[0].length ], category ] if match && !Text.after_for?(text, match.begin(0))
      end.min_by(&:first)&.last
    end

    # A keyword with up to two letters of ending: plural and case endings of Russian keywords.
    def keyword_patterns
      @keyword_patterns ||= categories.values.reject { |category| category.keywords.empty? }.map do |category|
        words = category.keywords.sort_by { |keyword| -keyword.length }.map { |keyword| "#{Regexp.escape(keyword)}\\p{L}{0,2}" }
        [ category, Text.word(words.join("|")) ]
      end
    end
  end
end
