require "test_helper"

module Extraction
  class TaggerTest < ActiveSupport::TestCase
    Row = Data.define(:card, :labels)

    test "words keep where they stand, so a span is cut from the text as written" do
      text = "Смартфон Kvazar K7, 8/256GB"
      tokens = Tagger.tokenize(text)

      assert_equal %w[Смартфон Kvazar K7 , 8 / 256GB], tokens.map(&:text)
      assert_equal [ Tagger::Span.new(attribute: "model", raw: "K7", start: 16) ],
                   Tagger.spans(text, tokens, %w[O B-brand B-model O O O O]).select { |span| span.attribute == "model" }
    end

    test "examples mark the gold value where it is written, rules or not" do
      rows = [ Row.new(card(title: "Смартфон Kvazar K7 Pro 128 ГБ"), { "brand" => "Kvazar", "model" => "K7 Pro", "storage" => "128 ГБ" }) ]
      example = Tagger::Examples.new(rows).each.first

      assert_equal %w[O B-brand B-model I-model B-storage I-storage], example.labels
    end

    test "the perceptron learns where a brand nobody listed stands" do
      brands = %w[Kvazar Orbita Zenit Plutos Veles Morok Tundra Sever Granit Altair]
      rows = brands.each_with_index.map do |brand, index|
        Row.new(card(title: "Смартфон #{brand} X#{index} 128 ГБ"), { "brand" => brand, "model" => "X#{index}", "storage" => "128 ГБ" })
      end
      perceptron = Tagger::Perceptron.train(Tagger::Examples.new(rows).each)

      assert_includes perceptron.spans("Смартфон Lumino X42 128 ГБ", category: "smartphone", source: "title", attributes: %w[brand model])
                                .map { |span| [ span.attribute, span.raw ] }, [ "brand", "Lumino" ]
    end

    test "the tagger reads only what the rules left unsettled, and its values come with their source" do
      tagger = Struct.new(:asked) do
        def rule = "fake"

        def spans(text, attributes:, **)
          self.asked = attributes
          text.include?("Lumino") ? [ Tagger::Span.new(attribute: "color", raw: "черный", start: 0) ] : []
        end
      end.new

      result = extract(tagger: tagger, title: "Смартфон Samsung Galaxy A55 8/256 ГБ Lumino")

      assert_not_includes tagger.asked, "brand"
      assert_includes tagger.asked, "color"
      assert_equal [ "черный", "tagger" ], [ result["color"].value, result["color"].source ]
    end

    test "the tagger does not restore a compatible device as an accessory's brand and model" do
      tagger = Class.new do
        attr_reader :asked

        def rule = "fake"

        def spans(text, attributes:, **)
          @asked = attributes
          [ Tagger::Span.new(attribute: "brand", raw: "Samsung", start: 20),
            Tagger::Span.new(attribute: "model", raw: "Galaxy S24", start: 28),
            Tagger::Span.new(attribute: "color", raw: "черный", start: 50) ].select { |span| attributes.include?(span.attribute) }
        end
      end.new

      result = extract(tagger: tagger, title: "Чехол для смартфона Samsung Galaxy S24 силиконовый черный")

      assert_equal "generic", result.category.name
      assert_not_includes tagger.asked, "brand"
      assert_not_includes tagger.asked, "model"
      assert result["brand"].missing?
      assert result["model"].missing?
      assert_equal "черный", result["color"].value
    end
  end
end
