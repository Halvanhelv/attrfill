require "zlib"

module Extraction
  module Tagger
    # An averaged perceptron labelling words left to right: each word by its own form, its neighbours,
    # the label just given and the category. Learns in seconds, labels a card in about a millisecond.
    class Perceptron
      EPOCHS = 5
      # Past this many texts learning only gets slower (minutes in plain Ruby), not much better.
      MAX_TEXTS = 12_000
      MIN_WEIGHT = 1e-3

      def self.load(path)
        new(JSON.parse(Zlib.gunzip(path.binread))) if path.exist?
      end

      def self.train(examples, epochs: EPOCHS, seed: 1)
        Training.new(examples.to_a.shuffle(random: Random.new(seed)).first(MAX_TEXTS), epochs: epochs, seed: seed).call
      end

      def initialize(data)
        @weights = data.fetch("weights")
        @labels = data.fetch("labels")
      end

      def rule = "perceptron"

      def save(path)
        path.dirname.mkpath
        path.binwrite(Zlib.gzip(JSON.generate("labels" => @labels, "weights" => @weights)))
      end

      # Spans of the attributes asked for, in one text.
      def spans(text, category:, source:, attributes:)
        tokens = Tagger.tokenize(text)
        tokens = tokens.first(DESCRIPTION_TOKENS) if source == "description"
        # Every label is in play: a word that holds an attribute not asked for must not be read as another one.
        Tagger.spans(text, tokens, label(tokens.map(&:text), category, source)).select { |span| attributes.include?(span.attribute) }
      end

      def label(words, category, source)
        words.each_index.with_object([]) do |index, labels|
          labels << best(Features.of(words, index, labels.last || "^", category, source))
        end
      end

      private

      def best(features)
        scores = Hash.new(0.0)
        features.each { |feature| @weights[feature]&.each { |label, weight| scores[label] += weight } }
        @labels.max_by { |label| [ scores[label], label == "O" ? 1 : 0 ] }
      end

      module Features
        module_function

        def of(words, index, previous, category, source) = fixed(words, index, category, source) + around(words, index, previous)

        # What does not depend on the labels already given: computed once a text when learning.
        def fixed(words, index, category, source)
          word = words[index].downcase
          before = words[index - 1]&.downcase if index.positive?
          after = words[index + 1]&.downcase
          [
            "b", "w=#{word}", "s=#{shape(words[index])}", "p3=#{word[0, 3]}", "x3=#{word[-3..]}",
            "w-1=#{before || '^'}", "w+1=#{after || '$'}", "w-2=#{index > 1 ? words[index - 2].downcase : '^'}",
            "w+2=#{words[index + 2]&.downcase || '$'}", "s+1=#{after ? shape(words[index + 1]) : '$'}",
            "c=#{category}", "cs=#{category}|#{shape(words[index])}", "cw+1=#{category}|#{after}", "src=#{source}|#{[ index, 4 ].min}"
          ]
        end

        def around(words, index, previous)
          [ "t-1=#{previous}", "t-1w=#{previous}|#{words[index].downcase}", "t-1s=#{previous}|#{shape(words[index])}" ]
        end

        # "Galaxy" → "Xx", "128GB" → "9X", "6,7" → "9,9"
        def shape(word)
          word.gsub(/\p{Lu}+/, "X").gsub(/\p{Ll}+/, "x").gsub(/\p{N}+/, "9")[0, 6]
        end
      end

      class Training
        def initialize(examples, epochs:, seed:)
          @examples = examples
          @epochs = epochs
          @random = Random.new(seed)
          @weights = Hash.new { |hash, feature| hash[feature] = Hash.new(0.0) }
          @totals = Hash.new(0.0)
          @stamps = Hash.new(0)
          @step = 0
        end

        def call
          labels = (@examples.flat_map(&:labels).uniq | [ "O" ]).sort

          @epochs.times do
            @examples.shuffle(random: @random).each do |example|
              previous = "^"
              example.tokens.each_index do |index|
                features = Features.of(example.tokens, index, previous, example.category, example.source)
                guess = guess(features, labels)
                truth = example.labels[index]
                update(features, truth, guess) if guess != truth
                @step += 1
                previous = truth
              end
            end
          end

          Perceptron.new("labels" => labels, "weights" => averaged)
        end

        private

        def guess(features, labels)
          scores = Hash.new(0.0)
          features.each { |feature| @weights.fetch(feature, nil)&.each { |label, weight| scores[label] += weight } }
          labels.max_by { |label| [ scores[label], label == "O" ? 1 : 0 ] }
        end

        def update(features, truth, guess)
          features.each do |feature|
            [ [ truth, 1.0 ], [ guess, -1.0 ] ].each do |label, change|
              key = [ feature, label ]
              @totals[key] += (@step - @stamps[key]) * @weights[feature][label]
              @stamps[key] = @step
              @weights[feature][label] += change
            end
          end
        end

        def averaged
          @weights.each_with_object({}) do |(feature, labels), result|
            kept = labels.filter_map do |label, weight|
              key = [ feature, label ]
              average = (@totals[key] + (@step - @stamps[key]) * weight) / [ @step, 1 ].max
              [ label, average.round(4) ] if average.abs >= MIN_WEIGHT
            end
            result[feature] = kept.to_h if kept.any?
          end
        end
      end
    end
  end
end
