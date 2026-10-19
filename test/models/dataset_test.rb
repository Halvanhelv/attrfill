require "test_helper"

class DatasetTest < ActiveSupport::TestCase
  def write(name, content)
    path = Rails.root.join("tmp", "#{SecureRandom.hex(4)}-#{name}")
    path.binwrite(content)
    @paths = [ *@paths, path ]
    path
  end

  teardown { Array(@paths).each(&:delete) }

  test "a CSV with gold columns" do
    row = Dataset.new(write("a.csv", "id,title,attributes,brand,color\n7,Смартфон X,\"{\"\"Цвет\"\": \"\"Black\"\"}\",Example,черный\n")).first

    assert_equal [ "7", "Смартфон X", { "цвет" => "Black" } ], [ row.card.id, row.card.title, row.card.seller_attributes ]
    assert_equal({ "brand" => "Example", "color" => "черный" }, row.labels)
  end

  test "a seller_attributes column is the seller's attributes, not one called attributes" do
    line = { id: "S1", title: "Смартфон X", seller_attributes: { "Цвет" => "синий" } }.to_json
    row = Dataset.new(write("s.jsonl", "#{line}\n")).first

    assert_equal({ "цвет" => "синий" }, row.card.seller_attributes)
  end

  test "Russian headers, semicolons and gold_ columns" do
    row = Dataset.new(write("b.csv", "Название;Описание;Характеристики;gold_brand\nНоутбук X;Текст;{'Бренд': 'Example'};Example\n")).first

    assert_equal [ "1", "Ноутбук X", "Текст", { "бренд" => "Example" } ],
                 [ row.card.id, row.card.title, row.card.description, row.card.seller_attributes ]
    assert_equal({ "brand" => "Example" }, row.labels)
  end

  test "JSON Lines with other field names and packed labels" do
    line = { sku: "A1", name: "Планшет X", text: "Описание", params: "Цвет: белый; ОЗУ: 8 ГБ", labels: { color: "белый" } }.to_json
    row = Dataset.new(write("c.jsonl", "#{line}\n\n")).first

    assert_equal [ "A1", "Планшет X", { "цвет" => "белый", "озу" => "8 ГБ" } ], [ row.card.id, row.card.title, row.card.seller_attributes ]
    assert_equal({ "color" => "белый" }, row.labels)
  end

  test "a JSON array with attributes as pairs and no gold" do
    row = Dataset.new(write("d.json", [ { id: 1, title: "ТВ", attributes: [ { name: "Бренд", value: "Example" } ] } ].to_json)).first

    assert_equal({ "бренд" => "Example" }, row.card.seller_attributes)
    assert_empty row.labels
  end

  test "Windows-1251, UTF-16 and a BOM are all read as text" do
    content = "id;title\r\n1;Смартфон чёрный\r\n"

    [ content.encode("Windows-1251"), "\xFF\xFE".b + content.encode("UTF-16LE").b, "\uFEFF#{content}" ].each do |bytes|
      assert_equal [ "1", "Смартфон черный" ], Dataset.new(write("e.csv", bytes)).first.card.then { |card| [ card.id, card.title ] }
    end
  end

  test "cards under a key, fields one level down, attributes one per column" do
    nested = { total: 1, data: [ { ID: 5, card: { Title: "ТВ", Description: "Текст" }, labels: { brand: "Example" } } ] }.to_json
    row = Dataset.new(write("f.json", nested)).first
    assert_equal [ "5", "ТВ", "Текст", { "brand" => "Example" } ], [ row.card.id, row.card.title, row.card.description, row.labels ]

    row = Dataset.new(write("g.tsv", "title\tattr_Бренд\tattr_Цвет\nТВ\tExample\t\n")).first
    assert_equal({ "бренд" => "Example" }, row.card.seller_attributes)
  end

  test "gold from a file of its own, wide or tall" do
    cards = write("h.csv", "id,title\na,Смартфон\nb,Ноутбук\n")
    wide = write("h.gold.csv", "id,brand,Цвет\na,Example,белый\n")
    tall = write("i.gold.csv", "id,attribute,value\nb,Бренд,Example\nb,color,серый\nb,unknown,x\n")

    assert_equal [ { "brand" => "Example", "color" => "белый" }, {} ], Dataset.new(cards, labels: wide).map(&:labels)
    assert_equal [ {}, { "brand" => "Example", "color" => "серый" } ], Dataset.new(cards, labels: tall).map(&:labels)
  end

  test "a missing file is said plainly" do
    assert_equal "File not found: nowhere.csv", assert_raises(ArgumentError) { Dataset.new("nowhere.csv") }.message
  end

  test "the learner adopts the way the dataset writes values" do
    rows = Array.new(8) { |index| "#{index},Смартфон Samsung Galaxy A#{index} 8/256GB Black 6.5\" 5000 мАч,SAMSUNG,256GB,8GB,\"6,5\",5000,Black" }
    train = write("style.csv", "id,title,brand,storage,ram,screen_diagonal,battery,color\n#{rows.join("\n")}\n")
    original = Extraction.config_root

    Dir.mktmpdir do |copy|
      FileUtils.cp_r("#{original}/.", copy)
      Extraction.config_root = Pathname(copy)
      Extraction.reload!
      Extraction::Learner.new(Dataset.new(train)).call.save!

      assert_equal({ "brand" => "SAMSUNG", "model" => "Galaxy A1", "storage" => "256GB", "ram" => "8GB", "screen_diagonal" => "6,5",
                     "battery" => "5000", "color" => "Black" }, values(extract(title: "Смартфон Samsung Galaxy A1 8/256GB чёрный 6.5\" 5000 мАч")))
      assert_equal "1TB", extract(title: "Смартфон Samsung Galaxy A1 12/1 ТБ")["storage"].value
    end
  ensure
    Extraction.config_root = original
    Extraction.reload!
  end

  test "predictions are written per attribute in CSV and per card in JSON" do
    result = extract(id: "9", title: "Смартфон Samsung Galaxy A15 4/128GB синий")
    csv, json = write("out.csv", ""), write("out.json", "")

    [ csv, json ].each { |path| Dataset::Writer.open(path) { |writer| writer << result << result } }

    assert_includes csv.read, "9,smartphone,storage,128 ГБ,0.9,accepted,title\n"
    assert_equal [ "9", "Samsung" ], JSON.parse(json.read).last.then { |card| [ card["id"], card.dig("attributes", "brand", "value") ] }
  end

  test "spreadsheet exports escape formula cells while machine CSV and JSON retain exact values" do
    [ "=1+1", "+SUM(A1:A2)", "-1+2", "@SUM(1)", "\t=1+1", "\r=1+1", "\n=1+1", "\uFEFF=1+1", "  =1+1" ].each do |formula|
      result = extract(id: "=ROW()", title: "Смартфон Samsung A15")
      result = result.with(findings: [ result["brand"].with(value: formula) ])
      safe = write("safe.csv", "")
      machine = write("machine.csv", "")
      json = write("exact.json", "")
      Dataset::Writer.open(safe, spreadsheet_safe: true) { |writer| writer << result }
      Dataset::Writer.open(machine) { |writer| writer << result }
      Dataset::Writer.open(json, spreadsheet_safe: true) { |writer| writer << result }
      assert_equal "'#{formula}", CSV.read(safe, headers: true).first["value"]
      assert_equal "'=ROW()", CSV.read(safe, headers: true).first["id"]
      assert_equal formula, CSV.read(machine, headers: true).first["value"]
      assert_equal formula, JSON.parse(json.read).first.dig("attributes", "brand", "value")
    end
  end

  test "evaluation reports labels outside the category and gold ranges separately from the main score" do
    evaluation = Evaluation.new(partial: true)
    phone = extract(title: "Смартфон Samsung Galaxy A15 4/128GB, 6.5\"", category: "smartphone")
    evaluation.add(phone, { "brand" => "samsung", "screen_diagonal" => "6.2 - 6.6\"", "power" => "15 Вт" })
    variants = evaluation.report["variants"]

    assert_equal({ "power" => 1 }, variants["out_of_scope_labels"])
    assert_equal({ "screen_diagonal" => 1 }, variants["in_range_values"])
    assert_equal 0.5, variants["macro_f1_in_scope"]
    assert_equal 1.0, variants["macro_f1_range_aware"]
    assert_in_delta 1.0 / 3, variants["macro_f1_all_labels"], 0.001
    assert_equal evaluation.report["macro_f1"], variants["macro_f1_in_scope"]
  end

  test "gold ranges are read as intervals" do
    assert_equal [ 15.0, 16.9 ], Evaluation::GoldRange.bounds("от 15 до 16.9")
    assert_equal [ 3000.0, 5000.0 ], Evaluation::GoldRange.bounds("3000-5000 мач")
    assert_equal [ 6.6, Float::INFINITY ], Evaluation::GoldRange.bounds("6.6\" и более")
    assert_nil Evaluation::GoldRange.bounds("55\"")
  end

  test "a model without its number is not the labelled model" do
    evaluation = Evaluation.new(partial: true)
    evaluation.add(extract(title: "Планшет Samsung Galaxy", category: "tablet"), { "model" => "Galaxy Tab A11" })
    assert_equal 0, evaluation.report["attributes"]["model"]["correct"]
  end

  test "evaluation counts precision, recall and what went to review" do
    evaluation = Evaluation.new
    evaluation.add(extract(title: "Смартфон Samsung Galaxy A15 4/128GB"), { "brand" => "samsung", "storage" => "256 ГБ", "color" => "синий" })
    counts = evaluation.report["attributes"]

    assert_equal [ 1.0, 1.0 ], counts["brand"].values_at("precision", "recall")
    assert_equal [ 0.0, 0.0 ], counts["storage"].values_at("precision", "recall")
    assert_equal [ 0.0, 0.0, 1 ], counts["color"].values_at("recall", "coverage", "missing")
  end

  test "the learner picks up unknown brands and measures the rules" do
    rows = Array.new(25) { |index| "#{index},Смартфон Kvazar K#{index} 8/256GB,Kvazar,256 ГБ" }
    learner = Extraction::Learner.new(Dataset.new(write("train.csv", "id,title,brand,storage\n#{rows.join("\n")}\n"))).call

    assert_equal({ "brands" => [ "Kvazar" ] }, learner.learned)
    assert_operator learner.calibration.fetch("storage/title/combo"), :>, 0.95
  end
end
