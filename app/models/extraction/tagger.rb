module Extraction
  # The learned layer between rules and the model: marks the words of a text that hold an attribute's value,
  # having learned from labelled cards where values stand. Two interchangeable implementations:
  # Perceptron (plain Ruby, learned by bin/learn) and Transformer (a fine-tuned BERT run through ONNX).
  module Tagger
    Span = Data.define(:attribute, :raw, :start)
    Token = Data.define(:text, :start, :stop)

    TOKEN = /[\p{L}\p{N}]+(?:[.,]\p{N}+)*|[^\s\p{L}\p{N}]/
    # What a tagger reads of a description: values stand near its start, and the rest only costs time.
    DESCRIPTION_TOKENS = 200

    module_function

    def tokenize(text) = text.to_enum(:scan, TOKEN).map { Token.new($~[0], $~.begin(0), $~.end(0)) }

    # TAGGER=off|perceptron|transformer; by default the perceptron when one was learned.
    def current
      return @current if defined?(@current)

      @current =
        case ENV.fetch("TAGGER", "perceptron")
        when "off" then nil
        when "transformer" then Transformer.load(Extraction.config_path("tagger/transformer"))
        else Perceptron.load(Extraction.config_path("tagger/perceptron.json.gz"))
        end
    end

    def reset!
      remove_instance_variable(:@current) if defined?(@current)
    end

    # Words labelled B-attribute / I-attribute turned back into the text they cover.
    def spans(text, tokens, labels)
      labels.each_with_index.with_object([]) do |(label, index), spans|
        next if label == "O"

        mark, attribute = label.split("-", 2)
        last = spans.last
        if mark == "I" && last&.attribute == attribute && last.stop == index
          last.stop = index + 1
        else
          spans << Struct.new(:attribute, :start, :stop).new(attribute, index, index + 1)
        end
      end.map do |span|
        first, last = tokens[span.start], tokens[span.stop - 1]
        Span.new(attribute: span.attribute, raw: text[first.start...last.stop], start: first.start)
      end
    end
  end
end
