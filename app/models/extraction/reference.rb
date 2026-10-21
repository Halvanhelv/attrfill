require "zlib"

module Extraction
  # Products met in labelled cards, by brand and model. A card of a known product (another colour or memory of
  # a model already seen) takes what that product's cards said, for the attributes its own text leaves unsettled.
  class Reference
    NAMING = %w[brand model].freeze

    def self.load(path)
      new(JSON.parse(Zlib.gunzip(path.binread))) if path.exist?
    end

    # REFERENCE=off turns it off; by default the one bin/learn built, if any.
    def self.current
      return @current if defined?(@current)

      @current = ENV["REFERENCE"] == "off" ? nil : load(Extraction.config_path("reference.json.gz"))
    end

    def self.reset!
      remove_instance_variable(:@current) if defined?(@current)
    end

    # Each card is keyed by the brand and model read from it, as they will be read from a card to fill.
    def self.build(rows, pipeline)
      products = Hash.new { |hash, key| hash[key] = Hash.new { |values, attribute| values[attribute] = Hash.new(0) } }
      keys = Extraction.in_parallel(rows) { |slice| slice.map { |row| pipeline.product_key(row.card) } }.flatten
      rows.zip(keys).each do |row, key|
        next unless key

        row.labels.each { |attribute, value| products[key][attribute][value] += 1 unless NAMING.include?(attribute) || value.blank? }
      end
      new(products)
    end

    def self.key(brand, model) = (Text.key("#{brand} #{model}") if brand.present? && model.present?)

    def initialize(products)
      @products = products
    end

    def size = @products.size

    # What the product's cards agree on, for the attributes asked; a value under half of them is not offered.
    def candidates(key, category, attributes)
      known = @products[key] or return []

      attributes.filter_map do |attribute|
        values = known[attribute.name].presence or next
        raw, seen = values.max_by(&:last)
        total = values.values.sum
        next if seen * 2 <= total

        rule = total == 1 ? "single" : seen == total ? "unanimous" : "majority"
        value = attribute.kind.normalize(raw, category: category) || (raw if attribute.kind.open?) or next
        Candidate.build(attribute: attribute.name, value: value, raw: raw, source: "reference", rule: rule)
      end
    end

    def save(path)
      path.dirname.mkpath
      path.binwrite(Zlib.gzip(JSON.generate(@products)))
    end
  end
end
