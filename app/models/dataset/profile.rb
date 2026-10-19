class Dataset
  # The exploratory look at a dataset: how full each field is, what sellers call their attributes,
  # which categories and gold values there are. Written to docs/eda.md.
  class Profile
    TOP = 15

    def initialize(dataset, catalog: Extraction::Catalog.current)
      @dataset = dataset
      @catalog = catalog
    end

    def to_markdown
      collect

      [ "# EDA", "", "Cards: **#{@rows}**, repeated ids: #{@ids.count { |_, count| count > 1 }}, " \
                     "repeated titles: #{@titles.count { |_, count| count > 1 }}.", "",
        "## Card fields", "", "| Field | Filled | Median length | Max length |", "|---|---|---|---|",
        *@lengths.map { |field, lengths| "| #{field} | #{share(lengths.count(&:positive?))} | #{median(lengths)} | #{lengths.max.to_i} |" },
        "", "## Categories", "", table("Category in the data", @given), "", table("Category by the rules", @detected),
        "", "## Seller attributes", "", "Average per card: #{(@seller_keys.values.sum.to_f / [ @rows, 1 ].max).round(1)}", "",
        table("Key", @seller_keys), "", "## Labels", "", *label_sections ].join("\n")
    end

    private

    def collect
      @rows = 0
      @ids, @titles, @given, @detected, @seller_keys = Array.new(5) { Hash.new(0) }
      @lengths = { "title" => [], "description" => [], "seller_attributes" => [] }
      @labels = Hash.new { |hash, name| hash[name] = Hash.new(0) }

      @dataset.each do |row|
        card = row.card
        @rows += 1
        @ids[card.id] += 1
        @titles[card.title.downcase] += 1
        @given[card.category || "—"] += 1
        @detected[@catalog.detect(card).label] += 1
        @lengths["title"] << card.title.length
        @lengths["description"] << card.description.length
        @lengths["seller_attributes"] << card.seller_attributes.size
        card.seller_attributes.each_key { |key| @seller_keys[key] += 1 }
        row.labels.each { |name, value| @labels[name][value] += 1 }
      end
    end

    def label_sections
      return [ "The file has no labelled fields." ] if @labels.empty?

      @labels.flat_map do |name, values|
        [ "### #{@catalog.attributes[name]&.label || name}", "",
          "Filled: #{share(values.values.sum)}, unique values: #{values.size}.", "", table("Value", values), "" ]
      end
    end

    def table(title, counts)
      [ "| #{title} | Cards | Share |", "|---|---|---|",
        *counts.sort_by { |_, count| -count }.first(TOP).map { |value, count| "| #{value.to_s.tr('|', '/').truncate(60)} | #{count} | #{share(count)} |" } ].join("\n")
    end

    def share(count) = @rows.zero? ? "0%" : "#{(100.0 * count / @rows).round(1)}%"

    def median(numbers) = numbers.empty? ? 0 : numbers.sort[numbers.size / 2]
  end
end
