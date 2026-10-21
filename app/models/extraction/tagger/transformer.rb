module Extraction
  module Tagger
    # A small BERT (rubert-tiny2) fine-tuned by script/ner/train.py and run through ONNX: the same words in,
    # the same labels out as the perceptron. Reads context better, costs ~10–30 ms of CPU a text.
    class Transformer
      MAX_PIECES = 320

      def self.load(dir)
        new(dir) if dir.join("model.onnx").exist?
      end

      def initialize(dir)
        @model = OnnxRuntime::Model.new(dir.join("model.onnx").to_s, intra_op_num_threads: ENV.fetch("TAGGER_THREADS", 1).to_i)
        @tokenizer = Tokenizers::Tokenizer.from_file(dir.join("tokenizer.json").to_s)
        @labels = JSON.parse(dir.join("labels.json").read)
      end

      def rule = "transformer"

      def spans(text, category:, source:, attributes:)
        tokens = Tagger.tokenize(text)
        tokens = tokens.first(DESCRIPTION_TOKENS) if source == "description"
        return [] if tokens.empty?

        Tagger.spans(text, tokens, label(tokens.map(&:text), category, source)).select { |span| attributes.include?(span.attribute) }
      end

      # The text is prefixed with its category and source, as in training; a word's label is its first piece's.
      def label(words, category, source)
        encoding = @tokenizer.encode([ category, "|", source, "|", *words ], is_pretokenized: true)
        ids = encoding.ids.first(MAX_PIECES)
        logits = @model.predict({ "input_ids" => [ ids ], "attention_mask" => [ Array.new(ids.size, 1) ] })["logits"].first

        labels = Array.new(words.size, "O")
        previous = nil
        encoding.word_ids.first(ids.size).each_with_index do |word, piece|
          next if word.nil? || word == previous || word < 4

          previous = word
          labels[word - 4] = @labels[logits[piece].each_with_index.max.last]
        end
        labels
      end
    end
  end
end
