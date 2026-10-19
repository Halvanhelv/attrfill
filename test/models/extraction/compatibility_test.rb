require "test_helper"

class Extraction::CompatibilityTest < ActiveSupport::TestCase
  class Tagger
    def initialize(model: "Galaxy S24")
      @model = model
    end

    def rule = "fake"

    def spans(text, **)
      { "brand" => "Samsung", "model" => @model }.filter_map do |attribute, raw|
        position = text.index(raw)
        Extraction::Tagger::Span.new(attribute: attribute, raw: raw, start: position) if position
      end
    end
  end

  test "the tagger cannot restore a compatible device as the accessory's own brand or model" do
    [ "Чехол для смартфона Samsung Galaxy S24 силиконовый",
     "Case for Samsung Galaxy S24", "Case compatible with Samsung Galaxy S24" ].each do |title|
      result = extract(title: title, tagger: Tagger.new)
      assert result["brand"].missing?, title
      assert result["model"].missing?, title
    end
  end

  test "device mentions in the description are excluded too" do
    result = extract(title: "Силиконовый чехол", description: "Совместим с Samsung Galaxy S24", tagger: Tagger.new)
    assert result["brand"].missing?
    assert result["model"].missing?
  end

  test "a tagger span starting inside the device model remains a compatibility mention" do
    result = extract(title: "Чехол для смартфона Samsung Galaxy S24", tagger: Tagger.new(model: "S24"))
    assert result["model"].missing?
  end

  test "a phone with a gift accessory keeps its own attributes" do
    result = extract(title: "Смартфон Samsung Galaxy S24 8/256GB + чехол в подарок", tagger: Tagger.new)
    assert_equal "Samsung", result["brand"].value
    assert_equal "Galaxy S24", result["model"].value
  end

  test "a usage phrase before the brand is not compatibility" do
    result = extract(title: "Смартфон для работы Samsung Galaxy S24", tagger: Tagger.new)
    assert_equal "Samsung", result["brand"].value
    assert_equal "Galaxy S24", result["model"].value
  end

  test "an accessory can still have its own brand and model before the compatibility phrase" do
    result = extract(title: "Чехол Apple Silicone для Samsung Galaxy S24", tagger: Tagger.new)
    assert_equal "Apple", result["brand"].value
    assert_equal "Silicone", result["model"].value
  end

  test "a human-only gate does not rerun machine inference on an already strong reading" do
    previous = ENV["ACCEPTANCE_MODE"]
    ENV["ACCEPTANCE_MODE"] = "strict"
    tagger = Struct.new(:asked) do
      def spans(_text, attributes:, **)
        self.asked = attributes
        []
      end
    end.new
    result = extract(title: "Смартфон Samsung Galaxy S24 черный", tagger: tagger,
                     seller_attributes: { "Бренд" => "Samsung", "Модель" => "Galaxy S24", "Цвет" => "черный" })
    assert result["model"].review?
    assert result["color"].review?
    assert_not_includes tagger.asked, "model"
    assert_not_includes tagger.asked, "color"
  ensure
    ENV["ACCEPTANCE_MODE"] = previous
  end

  test "binary UTF8 and explicitly encoded text are normalized without mutating the caller" do
    bytes = "Смартфон чёрный".b.freeze
    assert_equal "Смартфон черный", Extraction::Text.clean(bytes)
    assert_equal Encoding::BINARY, bytes.encoding
    assert_equal "Смартфон черный", Extraction::Text.clean("Смартфон чёрный".encode("Windows-1251"))
    cleaned = Extraction::Text.clean("\xFFbroken".b)
    assert cleaned.valid_encoding?
    assert_equal Encoding::UTF_8, cleaned.encoding
    assert extract(title: "\xFFbroken".b).findings.all?(&:missing?)
  end
end
