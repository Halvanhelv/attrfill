require "test_helper"

class Extraction::PipelineTest < ActiveSupport::TestCase
  test "a full card is read without a model" do
    result = extract(title: "Смартфон Samsung Galaxy S24 Ultra 12/256GB Titanium Black",
                     description: "Экран 6.8 дюйма, аккумулятор 5000 мАч",
                     seller_attributes: '{"Бренд": "Samsung", "Цвет": "чёрный"}')

    assert_equal "smartphone", result.category.name
    assert_equal({ "brand" => "Samsung", "model" => "Galaxy S24 Ultra", "storage" => "256 ГБ", "ram" => "12 ГБ",
                   "screen_diagonal" => '6.8"', "battery" => "5000 мАч", "color" => "черный" }, values(result))
    # Every value read is accepted; the card says nothing of the processor, resolution, matrix or refresh rate.
    assert result.findings.reject(&:missing?).all?(&:accepted?)
    assert_equal %w[cpu refresh_rate resolution screen_type], result.findings.select(&:missing?).map(&:attribute).sort
    assert_not result.asked_model
  end

  test "sources that agree are trusted more than either alone" do
    alone = extract(title: "Смартфон Samsung Galaxy A15")["brand"]
    agreed = extract(title: "Смартфон Samsung Galaxy A15", seller_attributes: "Бренд: Samsung")["brand"]

    assert_operator agreed.confidence, :>, alone.confidence
  end

  test "sources that disagree send the value to review" do
    finding = extract(title: "Смартфон Samsung Galaxy S24 8/256GB", description: "Также доступна версия на 128 ГБ")["storage"]

    assert finding.review?
    assert_equal "256 ГБ", finding.value
    assert_equal [ "128 ГБ" ], finding.alternatives
  end

  test "a value written on the card wins over a conflicting product reference" do
    finding = extract(title: "Планшет Huawei MatePad SE 6/64GB Black")["color"]

    assert_equal [ "черный", "title", "dictionary" ], [ finding.value, finding.source, finding.rule ]
    assert finding.accepted?
    assert_operator finding.confidence, :>=, 0.9
  end

  test "memory after a digit-ending model wins over a conflicting product reference" do
    result = extract(title: "Планшет Samsung Galaxy Tab A9+ 6/128GB")

    assert_equal [ "6 ГБ", "128 ГБ" ], [ result["ram"].value, result["storage"].value ]
    assert_equal "combo", result["ram"].rule
  end

  test "agreement does not hide a conflicting characteristic" do
    finding = extract(title: "Смартфон Samsung Galaxy S24 8/256GB", description: "Также доступна версия на 128 ГБ",
                      seller_attributes: "Встроенная память: 256 ГБ")["storage"]

    assert finding.review?
    assert_operator finding.confidence, :>=, 0.8
    assert_equal [ "128 ГБ" ], finding.alternatives
  end

  test "another brand mentioned in the description does not unsettle the title's" do
    finding = extract(title: "Ноутбук ASUS Vivobook 15 X1504ZA", description: "Совместим с аксессуарами Apple")["brand"]

    assert_equal "ASUS", finding.value
    assert finding.accepted?
  end

  test "what the card does not say is missing, not invented" do
    result = extract(title: "Смартфон")

    assert result.findings.all?(&:missing?)
    assert result.findings.all? { |finding| finding.confidence.zero? }
  end

  test "an accessory is not the device it fits" do
    result = extract(title: "Чехол для смартфона Samsung Galaxy S24 силиконовый")

    assert_equal "generic", result.category.name
    assert result["brand"].missing?
    assert result["model"].missing?
  end

  test "the category the dataset names wins over the title" do
    assert_equal "tv", extract(title: "Samsung UE50CU7100UXRU", category: "Телевизор").category.name
    assert_equal "tablet", extract(title: "Samsung Galaxy Tab S9 FE 6/128").category.name
    assert_equal "generic", extract(title: "Кроссовки Example V10").category.name
  end

  test "a card without a title is read from the opening of its description" do
    result = extract(title: "", description: "Смартфон Samsung Galaxy A15 4/128GB синий. Гарантия 12 месяцев.")

    assert_equal [ "smartphone", "Samsung", "Galaxy A15", "128 ГБ" ], [ result.category.name, *values(result).values_at("brand", "model", "storage") ]
  end

  test "a brand no dictionary knows is guessed by its place and left for review" do
    result = extract(title: "Смартфон Kvazar Orbit 5 8/256 ГБ")

    assert_equal [ "Kvazar", "Orbit 5" ], values(result).values_at("brand", "model")
    assert result["brand"].review?
  end

  test "words that only describe the product are passed over on the way to its brand" do
    assert_equal "Kvazar", extract(title: "Наушники True Wireless Kvazar Buds X3 черный")["brand"].value
  end

  test "a brand with a typo is read as the brand" do
    assert_equal "Samsung", extract(title: "Смартфон Samsnug Galaxy A15")["brand"].value
    assert_equal "realme", extract(title: "ТЕЛЕФОН RELAME C67 4/128")["brand"].value
  end

  test "two seller fields that disagree go to review" do
    finding = extract(title: "Смартфон", seller_attributes: "Цвет: черный; Цвет товара: розовый")["color"]

    assert finding.review?
    assert_equal %w[розовый черный], [ finding.value, *finding.alternatives ].sort
  end

  test "markup and entities are not part of the text" do
    result = extract(title: "✅ Смартфон Samsung Galaxy A15 ⚡", description: "<ul><li>Экран&nbsp;6,5&nbsp;дюйма</li><li>5000 мАч</li></ul>&laquo;Хит&raquo;")

    assert_equal [ '6.5"', "5000 мАч" ], values(result).values_at("screen_diagonal", "battery")
  end

  test "binary UTF-8 input is normalized before matching" do
    title = "Смартфон Samsung Galaxy A15 Black".dup.force_encoding(Encoding::ASCII_8BIT)

    assert_equal [ "Samsung", "черный" ], values(extract(title: title)).values_at("brand", "color")
  end

  test "an empty card is read as empty" do
    assert extract(title: nil, description: nil).findings.all?(&:missing?)
  end

  test "seller attributes are read from JSON, a Python dict, pairs and plain text" do
    [ '{"Бренд": "Acer"}', "{'Бренд': 'Acer'}", '[{"name": "Бренд", "value": "Acer"}]', "Бренд: Acer; Гарантия: 1 год",
      "Бренд=Acer" ].each do |written|
      assert_equal "Acer", extract(title: "Ноутбук", seller_attributes: written)["brand"].value, written
    end
  end

  test "a brand the dictionary does not know is kept as the seller wrote it" do
    finding = extract(title: "Смартфон Kvazar K7", seller_attributes: "Бренд: Kvazar")["brand"]

    assert_equal [ "Kvazar", "raw" ], [ finding.value, finding.rule ]
  end
end
