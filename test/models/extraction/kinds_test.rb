require "test_helper"

class Extraction::KindsTest < ActiveSupport::TestCase
  def kind(name) = Extraction::Catalog.current.attributes.fetch(name).kind
  def category(name) = Extraction::Catalog.current.categories.fetch(name)
  def scan(name, text, source: "title", in_category: "smartphone")
    kind(name).scan(Extraction::Text.clean(text), category: category(in_category), source: source).map(&:value)
  end

  test "a combined memory figure names both RAM and storage" do
    [ "8/256GB", "8/256 ГБ", "8 ГБ/256 ГБ", "8+256Gb", "8/256" ].each do |written|
      assert_equal [ "8 ГБ" ], scan("ram", "Смартфон X #{written} черный"), written
      assert_equal [ "256 ГБ" ], scan("storage", "Смартфон X #{written} черный"), written
    end
  end

  test "a model ending in a digit does not hide the following memory pair" do
    title = "Планшет Samsung Galaxy Tab A9+ 6/128GB"

    assert_equal [ "6 ГБ" ], scan("ram", title, in_category: "tablet")
    assert_equal [ "128 ГБ" ], scan("storage", title, in_category: "tablet")
  end

  test "terabytes are kept as terabytes" do
    assert_equal [ "1 ТБ" ], scan("storage", "Ноутбук 16/1 ТБ")
    assert_equal [ "1 ТБ" ], scan("storage", "SSD 1TB")
    assert_equal "1 ТБ", kind("storage").normalize("1024 ГБ")
  end

  test "a word beside the number says which memory it is" do
    text = "Оперативная память 8 ГБ, встроенная память 128 ГБ"

    assert_equal [ "8 ГБ" ], scan("ram", text, source: "description")
    assert_equal [ "128 ГБ" ], scan("storage", text, source: "description")
  end

  test "a bare figure is told by its size, with less confidence" do
    match = kind("storage").scan("iPhone 15 128GB Pink", category: category("smartphone"), source: "title").sole

    assert_equal [ "128 ГБ", "bare" ], [ match.value, match.rule ]
    assert_empty scan("ram", "iPhone 15 128GB Pink")
  end

  test "the word after a number wins over the word before it" do
    assert_equal [ "6 ГБ" ], scan("ram", "Smartphone X 6GB RAM 64GB storage")
    assert_equal [ "64 ГБ" ], scan("storage", "Smartphone X 6GB RAM 64GB storage")
  end

  test "a number with a unit is read for any attribute the catalog describes" do
    assert_equal [ "165 Гц" ], scan("refresh_rate", "Монитор X 27\" 165Hz IPS", in_category: "monitor")
    assert_equal [ "1500 Вт" ], scan("power", "Пылесос X G10 1,5 кВт", in_category: "vacuum")
    assert_equal [ "310 л" ], scan("volume", "Холодильник X RB390N4AW1 310 л", in_category: "refrigerator")
    assert_equal [ "1200 об/мин" ], scan("spin_speed", "Стиральная машина X 6 кг 1 200 об/мин", in_category: "washing_machine")
    assert_equal "7 кг", kind("load").normalize("7")
  end

  test "a model's digit is not the battery's thousand" do
    assert_equal [ "300 мАч" ], scan("battery", "Умные часы Amazfit GTR 4 300 мАч", in_category: "smartwatch")
    assert_equal [ "4300 мАч" ], scan("battery", "Смартфон X 4 300 мАч")
  end

  test "a date is not memory" do
    assert_empty scan("storage", "Дата выпуска 10/2024")
    assert_empty scan("ram", "Дата выпуска 10/2024")
  end

  test "a diagonal is read in any of its notations" do
    [ '6.7"', "6,7 дюйма", "6.7''", "6.7″", "6.7 inch", "диагональ экрана 6.7" ].each do |written|
      assert_equal [ '6.7"' ], scan("screen_diagonal", "Экран #{written} AMOLED", source: "description"), written
    end
  end

  test "a diagonal no product of the category has is dropped" do
    assert_empty scan("screen_diagonal", 'Смартфон с экраном 55"')
    assert_equal [ '55"' ], scan("screen_diagonal", 'Телевизор 55"', in_category: "tv")
    assert_empty scan("screen_diagonal", "Экран 120 Гц", source: "description")
  end

  test "a screen's size is read from its model code, only where codes carry it" do
    assert_equal [ '50"' ], scan("screen_diagonal", "Телевизор TCL 50P7K", in_category: "tv")
    assert_equal [ '27"' ], scan("screen_diagonal", "Монитор Samsung S27D300GAI", in_category: "monitor")
    assert_equal [ '65"' ], scan("screen_diagonal", "Телевизор Haier 65 Smart TV S6", in_category: "tv")
    assert_empty scan("screen_diagonal", "Монитор 2024г выпуска", in_category: "monitor")
    assert_empty scan("screen_diagonal", "Ноутбук MSI Q16RTX", in_category: "laptop")
  end

  test "a battery is read with a split thousand and either unit" do
    assert_equal [ "5000 мАч" ], scan("battery", "Аккумулятор 5 000 мА·ч", source: "description")
    assert_equal [ "5160 мАч" ], scan("battery", "5160mAh", source: "description")
    assert_equal "5000 мАч", kind("battery").normalize("5000")
  end

  test "a colour is normalized from any form, language or gender" do
    { "чёрная" => "черный", "Black" => "черный", "серого" => "серый", "Space Gray" => "серый", "тёмно-синий" => "синий" }.each do |written, canonical|
      assert_equal [ canonical ], scan("color", "Смартфон X #{written}"), written
    end

    assert_empty scan("color", "Серия X, белье", source: "description")
  end

  test "a brand is read by name, in Cyrillic, or by its product line" do
    assert_equal [ "Samsung" ], scan("brand", "Смартфон Самсунг A15")
    assert_equal [ "Apple" ], scan("brand", "iPhone 15 128GB")
    assert_equal "product_line", kind("brand").scan("iPhone 15", category: category("smartphone"), source: "title").sole.rule
  end

  test "a model is what follows the brand, up to the first characteristic" do
    { "Смартфон Samsung Galaxy S24 Ultra 12/256GB Black" => "Galaxy S24 Ultra",
      "Apple iPhone 15 Pro Max 256 ГБ синий" => "iPhone 15 Pro Max",
      "Xiaomi Redmi Note 13 8/256" => "Redmi Note 13",
      'Телевизор LG 55UR78006LK 55" 4K' => "55UR78006LK",
      'Ноутбук ASUS Vivobook 15 X1504ZA 15.6" FHD' => "Vivobook 15 X1504ZA",
      "Смартфон realme 12 Pro+ 8/256 ГБ" => "12 Pro+",
      "Samsung Galaxy A15, синий" => "Galaxy A15" }.each do |title, model|
      assert_equal [ model ], scan("model", title), title
    end
  end

  test "a model is not looked for outside the title" do
    assert_empty scan("model", "Samsung Galaxy S24", source: "description")
  end

  test "the seller's model loses a repeated brand" do
    assert_equal "Galaxy S24", kind("model").normalize("Samsung Galaxy S24")
  end

  test "two ways of saying one model are the same model" do
    assert kind("model").same?("Galaxy S24 Ultra", "galaxy s24 ultra 5G")
    assert_not kind("model").same?("Galaxy S24", "Galaxy A15")
  end

  test "a processor is recognised by its shape" do
    assert_equal [ "Intel Core i5-1235U" ], scan("cpu", "Ноутбук X Intel Core i5-1235U/16 ГБ", in_category: "laptop")
    assert_equal [ "Ryzen 7 7730U" ], scan("cpu", "Ноутбук X Ryzen 7 7730U", in_category: "laptop")
    assert_equal [ "Apple M2" ], scan("cpu", "MacBook Air Apple M2 8/256", in_category: "laptop")
  end

  test "mount dimensions do not hide the screen resolution" do
    assert_equal [ "Full HD" ], scan("resolution", "VESA 100x100; разрешение 1920x1080", in_category: "monitor")
    assert_equal [ "4K UHD" ], scan("resolution", "VESA 300x300. Экран 4K UHD", in_category: "tv")
    assert_empty scan("resolution", "Крепление VESA 600x600", in_category: "tv")
    assert_empty scan("resolution", "Габариты 1200x800 мм", in_category: "tv")
    assert_equal [ "1920x1200" ], scan("resolution", "Монитор 1920x1200", in_category: "monitor")
  end
end
