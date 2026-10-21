module Extraction
  module Tagger
    # Labelled cards turned into words with B/I/O labels: where in the title or description each gold value stands.
    # A value is found where a rule read it (its raw text), else where it is written as in the labels.
    class Examples
      Example = Data.define(:tokens, :labels, :category, :source)

      def initialize(rows, catalog: Catalog.current)
        @rows = rows
        @catalog = catalog
        @pipeline = Pipeline.new(catalog: catalog, llm: nil, tagger: nil)
      end

      def each(&)
        return to_enum(:each) unless block_given?

        @rows.each do |row|
          next if row.labels.empty?

          category = @catalog.detect(row.card)
          readings = @pipeline.candidates(row.card, category)
          { "title" => row.card.heading, "description" => row.card.description }.each do |source, text|
            next if text.blank?

            yield example(text, source, category, row.labels, readings.select { |candidate| candidate.source == source })
          end
        end
      end

      private

      def example(text, source, category, gold, readings)
        tokens = Tagger.tokenize(text)
        tokens = tokens.first(DESCRIPTION_TOKENS) if source == "description"
        labels = Array.new(tokens.size, "O")

        category.attributes.each do |attribute|
          # Fields generated from a dataset are left to rules and known products: thousands of labels would swamp it.
          next if attribute.options["generated"]

          value = gold[attribute.name].presence or next

          places(text, attribute, value, readings).each do |start, stop|
            covered = tokens.each_index.select { |index| tokens[index].start >= start && tokens[index].stop <= stop }
            next if covered.empty? || covered.any? { |index| labels[index] != "O" }

            covered.each_with_index { |index, nth| labels[index] = "#{nth.zero? ? 'B' : 'I'}-#{attribute.name}" }
          end
        end

        Example.new(tokens: tokens.map(&:text), labels: labels, category: category.name, source: source)
      end

      # Character ranges of the gold value: what a rule read and got right, or the value as the labels write it.
      def places(text, attribute, value, readings)
        kind = attribute.kind
        gold = kind.normalize(value) || value
        raws = readings.select { |candidate| candidate.attribute == attribute.name && kind.same?(candidate.value, gold) }.map(&:raw)
        raws << value

        raws.uniq.filter_map do |raw|
          match = text.match(Text.word(Regexp.escape(raw)))
          [ match.begin(0), match.end(0) ] if match
        end.first(1)
      end
    end
  end
end
