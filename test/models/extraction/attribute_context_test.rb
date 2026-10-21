require "test_helper"

class Extraction::AttributeContextTest < ActiveSupport::TestCase
  def scan(name, text, category:)
    catalog = Extraction::Catalog.current
    catalog.attributes.fetch(name).kind.scan(text, category: catalog.categories.fetch(category), source: "description").map(&:value)
  end

  test "television power excludes its speakers" do
    assert_equal [ "65 Вт" ], scan("power", "Потребляемая мощность 65 Вт. Два динамика мощностью 20 Вт.", category: "tv")
  end

  test "monitor power excludes USB power delivery" do
    assert_equal [ "35 Вт" ], scan("power", "USB-C с Power Delivery 90W. Потребляемая мощность 35 Вт.", category: "monitor")
  end

  test "energy consumption is not electric power" do
    [ "кВт*ч", "кВт•ч", "кВт ч" ].each do |unit|
      assert_empty scan("power", "Энергопотребление за цикл 1,2 #{unit}.", category: "washing_machine")
    end
  end

  test "an energy unit before its number is not interpreted as power" do
    assert_empty scan("power", "Энергопотребление (кВт*ч): 1,2", category: "washing_machine")
    assert_equal [ "65 Вт" ], scan("power", "Потребляемая мощность (Вт): 65", category: "tv")
  end

  test "vacuum consumption is distinct from suction power" do
    assert_equal [ "1600 Вт" ], scan("power", "Мощность всасывания 350 Вт. Потребляемая мощность 1600 Вт.", category: "vacuum")
  end

  test "an unqualified product wattage remains available" do
    assert_equal [ "1200 Вт" ], scan("power", "Пылесос Example 1200 Вт", category: "vacuum")
  end

  test "a new power field ends the preceding speaker context" do
    assert_equal [ "100 Вт" ], scan("power", "Мощность динамиков: 20 Вт, мощность: 100 Вт", category: "tv")
    assert_empty scan("power", "Динамики мощностью 20 Вт", category: "tv")
  end

  test "seller suction power is not the consumption attribute" do
    result = extract(title: "Пылесос Example", seller_attributes: "Мощность всасывания: 350 Вт; Потребляемая мощность: 1600 Вт")
    assert_equal "1600 Вт", result["power"].value
    assert_empty result["power"].alternatives
  end

  test "an explicit total volume takes precedence over compartments" do
    assert_equal [ "330 л" ], scan("volume", "Общий объем 330 л. Холодильная камера 230 л, морозильная камера 100 л.", category: "refrigerator")
  end

  test "a refrigerator total can be derived from its two named compartments" do
    assert_equal [ "310 л" ], scan("volume", "Объем холодильной камеры 215 литров. Объем морозильной камеры 95 литров.", category: "refrigerator")
  end

  test "a freshness drawer is not counted twice in refrigerator volume" do
    assert_equal [ "381 л" ], scan("volume", "Холодильная камера объемом 222 л, зона свежести 21 л. Морозильная камера 159 л.", category: "refrigerator")
  end

  test "ambiguous compartment volumes are not added" do
    values = scan("volume", "Холодильная камера 220 л или 250 л. Морозильная камера 100 л.", category: "refrigerator")
    assert_not_includes values, "320 л"
    assert_not_includes values, "350 л"
  end

  test "a compartment included in another volume is not added again" do
    values = scan("volume", "Объем холодильной камеры 200 л (в том числе морозильная камера 50 л).", category: "refrigerator")
    assert_not_includes values, "250 л"
  end

  test "gross and usable compartment volumes are not mixed" do
    values = scan("volume", "Полный объем холодильной камеры 250 л. Полезный объем морозильной камеры 80 л.", category: "refrigerator")
    assert_not_includes values, "330 л"
  end

  test "trailing inclusion language prevents a compartment sum" do
    values = scan("volume", "Морозильная камера 50 л. Холодильная камера 200 л, включая морозильную камеру.", category: "refrigerator")
    assert_not_includes values, "250 л"
  end

  test "parenthesized gross and usable qualifiers prevent a sum" do
    values = scan("volume", "Объем холодильной камеры (полный) 250 л. Объем морозильной камеры (полезный) 80 л.", category: "refrigerator")
    assert_not_includes values, "330 л"
  end

  test "volume bases following the measurements are not mixed" do
    values = scan("volume", "Холодильная камера 250 л (брутто). Морозильная камера 80 л (нетто).", category: "refrigerator")
    assert_not_includes values, "330 л"
  end

  test "a computed compartment total stays a cautious reading" do
    description = "Холодильная камера 215 л. Морозильная камера 95 л."
    result = extract(title: "Холодильник Example", description: description)
    assert_equal "310 л", result["volume"].value
    assert_equal "component_sum", result["volume"].rule
    assert_operator result["volume"].confidence, :<, 0.8
    assert result["volume"].review?
    assert_includes description, result["volume"].raw
  end

  test "equal compartment amounts retain evidence of both readings" do
    description = "Холодильная камера 100 л. Морозильная камера 100 л."
    result = extract(title: "Холодильник Example", description: description)
    assert_equal "200 л", result["volume"].value
    assert_equal 2, result["volume"].raw.scan("100").size
    assert_includes description, result["volume"].raw
  end

  test "Apple A series chips are read from explicit processor names" do
    assert_equal [ "Apple A13 Bionic" ], scan("cpu", "Процессор Apple A13 Bionic с шестью ядрами", category: "smartphone")
    assert_equal [ "A17 Pro" ], scan("cpu", "Процессор A17 Pro", category: "smartphone")
  end

  test "a Galaxy A model is not an Apple processor" do
    assert_empty scan("cpu", "Смартфон Samsung Galaxy A13", category: "smartphone")
  end

  test "Intel processors retain a graphics suffix containing a digit" do
    assert_equal [ "Intel Core i5-1155G7" ], scan("cpu", "Ноутбук Intel Core i5-1155G7/8GB", category: "laptop")
    assert_equal [ "Intel Core i3 1005G1" ], scan("cpu", "Процессор Intel Core i3 1005G1", category: "laptop")
  end

  test "entry Intel processors accept their explicit J and N names" do
    assert_equal [ "Intel Celeron J4125" ], scan("cpu", "Ноутбук Intel Celeron J4125/8GB", category: "laptop")
    assert_equal [ "Intel N100" ], scan("cpu", "Ноутбук Intel N100/8GB", category: "laptop")
  end

  test "Ryzen model numbers accept hyphens and mixed alphanumeric suffixes" do
    assert_equal [ "AMD Ryzen 3-3200U" ], scan("cpu", "Процессор AMD Ryzen 3-3200U", category: "laptop")
    assert_equal [ "AMD Ryzen 9 9955HX3D" ], scan("cpu", "Процессор AMD Ryzen 9 9955HX3D", category: "laptop")
    assert_equal [ "AMD Ryzen 7 260" ], scan("cpu", "Процессор AMD Ryzen 7 260", category: "laptop")
  end

  test "an explicit processor family remains a cautious partial reading" do
    result = extract(title: "Ноутбук Example с процессором Intel Core i5")
    assert_equal "Intel Core i5", result["cpu"].value
    assert_equal "family", result["cpu"].rule
    assert result["cpu"].review?
  end

  test "alternative processor families are not guessed" do
    assert_empty scan("cpu", "Доступны варианты Intel Core i5 и AMD Ryzen 5", category: "laptop")
  end

  test "processor family fallback does not turn a phone model into Apple silicon" do
    assert_empty scan("cpu", "Смартфон POCO M5", category: "smartphone")
  end

  test "a battery unit accepts a mixed Latin A and Cyrillic letters" do
    assert_equal [ "7000 мАч" ], scan("battery", "Емкость батареи 7000 мAч", category: "tablet")
  end

  test "spin speed accepts the full Russian minute unit" do
    assert_equal [ "1500 об/мин" ], scan("spin_speed", "Максимальный отжим 1500 об/минуту", category: "washing_machine")
  end
end
