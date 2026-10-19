require "csv"

# A file of cards, CSV / TSV / JSON / JSON Lines in UTF-8, UTF-16 or Windows-1251, read row by row
# whatever its columns are called. Gold labels come from the same file or from one of their own.
class Dataset
  include Enumerable

  Row = Data.define(:card, :labels)

  CONFIG = YAML.load_file(Rails.root.join("config/dataset.yml")).freeze
  GOLD_AFFIXES = [ "gold_%s", "true_%s", "%s_true", "%s_gold" ].freeze

  def initialize(path, labels: nil, catalog: Extraction::Catalog.current)
    @source = Source.new(path)
    @catalog = catalog
    @external = labels.presence && external_labels(Source.new(labels))
  end

  def each
    return to_enum(:each) unless block_given?

    @source.records.each_with_index do |record, index|
      card = card_from(record, index)
      yield Row.new(card: card, labels: @external ? @external.fetch(card.id.to_s, {}) : labels(record))
    end
  end

  private

  attr_reader :catalog

  def card_from(record, index)
    fields = CONFIG.fetch("columns").transform_values { |names| record.values_at(*names).compact.first }
    fields["seller_attributes"] = spread_attributes(record).presence || fields["seller_attributes"]

    Extraction::Card.build(**fields.symbolize_keys, id: fields["id"].to_s.strip.presence || (index + 1).to_s)
  end

  def spread_attributes(record)
    CONFIG.fetch("seller_prefixes").each_with_object({}) do |prefix, found|
      # "seller_attributes" is the packed column, not one attribute called "attributes".
      record.each { |key, value| found[key.delete_prefix(prefix)] = value if key.start_with?(prefix) && value.present? && !card_field?([ key ]) }
    end
  end

  # Packed gold first, then an affixed column, then a column named like the attribute.
  def labels(record)
    packed = Extraction::SellerAttributes.parse(record.values_at(*CONFIG.fetch("labels")).compact.first)
    found = {}

    [ [ packed, gold_names ], [ record, gold_columns ] ].each do |values, columns|
      values.each do |key, value|
        attribute, rank = columns[key]
        next if attribute.nil? || value.to_s.strip.blank?

        known = found[attribute.name]
        found[attribute.name] = [ rank, value ] if known.nil? || rank < known.first
      end
    end

    found.transform_values { |_, value| Extraction::Text.clean(value) }
  end

  # Columns are looked up by name: a catalog of thousands of attributes is not walked for every card.
  def gold_names
    @gold_names ||= catalog.attributes.values.each_with_object({}) do |attribute, names|
      [ attribute.name, Extraction::Text.key(attribute.title) ].each { |name| names[name] ||= [ attribute, 0 ] }
    end
  end

  def gold_columns
    @gold_columns ||= catalog.attributes.values.each_with_object({}) do |attribute, columns|
      names = [ attribute.name, Extraction::Text.key(attribute.title) ]
      names.product(GOLD_AFFIXES).each { |name, affix| columns[format(affix, name)] ||= [ attribute, 1 ] }
      names.each { |name| columns[name] ||= [ attribute, 2 ] } unless card_field?(names)
    end
  end

  # A column called like an attribute is gold, unless that name is one of the card's own fields.
  def card_field?(names) = (CONFIG.fetch("columns").values.flatten & names).any?

  # { card id => labels } from a gold file, wide (a column per attribute) or tall (a line per attribute).
  def external_labels(source)
    tall = CONFIG.fetch("tall")
    ids = CONFIG.dig("columns", "id")

    source.records.each_with_object({}) do |record, found|
      id = record.values_at(*ids).compact.first.to_s.strip
      name = record.values_at(*tall["attribute"]).compact.first

      if name
        attribute = attribute_called(name) or next
        value = record.values_at(*tall["value"]).compact.first
        (found[id] ||= {})[attribute.name] = Extraction::Text.clean(value) if value.to_s.strip.present?
      else
        found[id] = labels(record)
      end
    end
  end

  def attribute_called(name)
    key = Extraction::Text.key(name)
    catalog.attributes.values.find { |attribute| key == attribute.name || key == Extraction::Text.key(attribute.title) }
  end

  # The file itself: its format, its encoding, its records as hashes with lowercased keys.
  class Source
    def initialize(path)
      @path = Pathname(path)
      raise ArgumentError, "File not found: #{@path}" unless @path.file?
    end

    def records
      found =
        case @path.extname.downcase
        when ".json" then json(JSON.parse(text))
        when ".jsonl", ".ndjson" then text.each_line.lazy.reject(&:blank?).map { |line| JSON.parse(line) }
        else csv
        end

      found.lazy.select { |record| record.is_a?(Hash) }.map { |record| flatten(record) }
    end

    private

    def json(parsed)
      return parsed if parsed.is_a?(Array)

      parsed.values_at(*CONFIG.fetch("containers")).compact.find { |value| value.is_a?(Array) } ||
        parsed.values.find { |value| value.is_a?(Array) } || [ parsed ]
    end

    def csv
      content = text
      first = content.each_line.first.to_s
      separator = @path.extname.casecmp?(".tsv") || first.count("\t") > first.count(",") + first.count(";") ? "\t" : first.count(";") > first.count(",") ? ";" : ","

      CSV.parse(content, headers: true, col_sep: separator, liberal_parsing: true, skip_blanks: true).lazy.map(&:to_h)
    end

    # A card's fields may sit one level down ({"card": {"title": …}}); keys are compared lowercased.
    def flatten(record)
      record = record.transform_keys { |key| key.to_s.strip.downcase }
      nested = record.slice(*CONFIG.fetch("nested")).values.select { |value| value.is_a?(Hash) }

      nested.reduce(record) { |merged, inner| inner.transform_keys { |key| key.to_s.strip.downcase }.merge(merged.except(*CONFIG.fetch("nested"))) }
    end

    # UTF-8 with or without a BOM, UTF-16 by its BOM, anything else taken for Windows-1251.
    def text
      bytes = @path.binread

      if bytes.start_with?("\xFF\xFE".b) then bytes.force_encoding("UTF-16LE").encode("UTF-8")[1..]
      elsif bytes.start_with?("\xFE\xFF".b) then bytes.force_encoding("UTF-16BE").encode("UTF-8")[1..]
      else
        utf8 = bytes.dup.force_encoding("UTF-8").delete_prefix("﻿")
        utf8.valid_encoding? ? utf8 : bytes.force_encoding("Windows-1251").encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
      end
    end
  end
end
