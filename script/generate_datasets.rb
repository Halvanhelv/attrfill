# Writes synthetic datasets in the shapes a real one may come in, so every reader path and every rule is exercised
# before the real data arrives:  ruby script/generate_datasets.rb [dir] [large_rows]
# Gold is filled only for what the card really says, plus a little that it does not (a recall no reader can reach).
require "json"
require "csv"
require "fileutils"

RNG = Random.new(42)
def pick(list) = list[RNG.rand(list.size)]
def chance(share) = RNG.rand < share

# "Kvazar" and "Nordbook" are invented: brands no dictionary knows, for the learner to pick up.
PRODUCTS = {
  "smartphone" => { "Samsung" => [ "Galaxy S24", "Galaxy S24 Ultra", "Galaxy A55 5G", "Galaxy A15" ],
                    "Apple" => [ "iPhone 15", "iPhone 15 Pro Max", "iPhone 13" ],
                    "Xiaomi" => [ "Redmi Note 13", "Redmi 13C", "14T Pro" ], "realme" => [ "12 Pro+", "C67" ],
                    "HONOR" => [ "X8b", "90 Lite" ], "Tecno" => [ "Spark 20", "Camon 30" ], "Kvazar" => [ "K7 Lite", "Orbit 5" ] },
  "laptop" => { "ASUS" => [ "Vivobook 15 X1504ZA", "Zenbook 14 UX3405MA" ], "Lenovo" => [ "IdeaPad Slim 3 15IAH8", "ThinkBook 16 G6" ],
                "HP" => [ "250 G10", "Pavilion 15-eg3000" ], "Acer" => [ "Aspire 5 A515-58M", "Swift Go 14" ],
                "Apple" => [ "MacBook Air 13", "MacBook Pro 14" ], "MSI" => [ "Modern 15 B13M" ], "Nordbook" => [ "N15 Pro", "Air 14" ] },
  "tablet" => { "Samsung" => [ "Galaxy Tab S9 FE", "Galaxy Tab A9+" ], "Apple" => [ "iPad Air 5", "iPad mini 6" ],
                "Xiaomi" => [ "Redmi Pad SE", "Pad 6" ], "Huawei" => [ "MatePad 11.5", "MatePad SE" ] },
  "tv" => { "LG" => [ "55UR78006LK", "OLED48C3RLA" ], "Samsung" => [ "UE50CU7100UXRU", "QE55Q60CAUXRU" ],
            "Hisense" => [ "43A6K", "65U7KQ" ], "TCL" => [ "65C745", "50P635" ], "Haier" => [ "S1 Smart TV", "S4 QLED" ] }
}.freeze

CATEGORY_WORDS = { "smartphone" => %w[Смартфон Телефон], "laptop" => %w[Ноутбук Ультрабук], "tablet" => %w[Планшет], "tv" => %w[Телевизор] }.freeze
CATEGORY_TITLES = { "smartphone" => "Смартфон", "laptop" => "Ноутбук", "tablet" => "Планшет", "tv" => "Телевизор" }.freeze
DIAGONALS = { "smartphone" => [ 6.1, 6.5, 6.67, 6.7, 6.8 ], "laptop" => [ 13.3, 14, 15.6, 16, 17.3 ], "tablet" => [ 8.3, 10.9, 11, 12.4 ], "tv" => [ 32, 43, 50, 55, 65 ] }.freeze
COLORS = { "черный" => %w[чёрный Black черная], "белый" => %w[белый White белая], "серый" => %w[серый Gray графит], "синий" => %w[синий Blue синяя],
           "зеленый" => %w[зелёный Green], "серебристый" => %w[серебристый Silver], "золотой" => %w[золотой Gold], "фиолетовый" => %w[фиолетовый Purple] }.freeze
CPUS = [ "Intel Core i5-1235U", "Intel Core i7-13620H", "AMD Ryzen 5 7520U", "AMD Ryzen 7 7730U", "Apple M2", "Intel Celeron N4500" ].freeze
RESOLUTIONS = { "4K UHD" => [ "4K UHD", "4K", "Ultra HD" ], "Full HD" => [ "Full HD", "FHD" ], "HD" => [ "HD Ready", "HD" ] }.freeze
CYRILLIC = { "Samsung" => "Самсунг", "Xiaomi" => "Сяоми", "Lenovo" => "Леново", "Huawei" => "Хуавей" }.freeze
FLUFF = [ "Официальная гарантия производителя.", "Быстрая доставка по всей России.", "Отличный выбор для работы и учёбы.",
          "Стильный дизайн и высокая производительность.", "В комплекте зарядное устройство и документация." ].freeze
KEYS = { "brand" => %w[Бренд Производитель Марка], "model" => [ "Модель" ], "storage" => [ "Встроенная память", "Объем памяти", "Накопитель" ],
         "ram" => [ "Оперативная память", "ОЗУ" ], "screen_diagonal" => [ "Диагональ экрана", "Диагональ" ], "battery" => [ "Емкость аккумулятора" ],
         "color" => [ "Цвет", "Цвет товара" ], "cpu" => [ "Процессор" ], "resolution" => [ "Разрешение экрана" ] }.freeze

def memory(gb) = gb >= 1024 ? "#{gb / 1024} ТБ" : "#{gb} ГБ"
def inches(number) = number.to_s.sub(/\.0\z/, "")

# One product with its true values, then a card that says some of them in some of the usual ways.
def card(index, noise:)
  category = pick(PRODUCTS.keys)
  brand = pick(PRODUCTS[category].keys)
  model = pick(PRODUCTS[category][brand])
  color = pick(COLORS.keys)
  diagonal = pick(DIAGONALS[category])
  phone = %w[smartphone tablet].include?(category)
  ram = pick(phone ? [ 4, 6, 8, 12 ] : [ 8, 16, 32 ])
  storage = pick(phone ? [ 64, 128, 256, 512 ] : [ 256, 512, 1024 ])
  truth = { "brand" => brand, "model" => model, "color" => color, "screen_diagonal" => "#{inches(diagonal)}\"" }
  truth.merge!("ram" => memory(ram), "storage" => memory(storage)) unless category == "tv"
  truth["battery"] = "#{pick([ 4500, 5000, 5160, 6000, 8000 ])} мАч" if phone
  truth["cpu"] = pick(CPUS) if category == "laptop"
  truth["resolution"] = pick(RESOLUTIONS.keys) if category == "tv"

  said = %w[brand model]
  shown_brand = noise && CYRILLIC[brand] && chance(0.15) ? CYRILLIC[brand] : brand
  title = [ (pick(CATEGORY_WORDS[category]) if !noise || chance(0.8)), shown_brand, model ].compact

  if category != "tv" && chance(noise ? 0.7 : 0.9)
    title << pick([ "#{ram}/#{storage}GB", "#{ram}/#{storage} ГБ", "#{ram} ГБ/#{memory(storage)}", "#{ram}/#{storage}" ]).sub("1024GB", "1TB").sub("1024 ГБ", "1 ТБ").sub("/1024", "/1 ТБ")
    said += %w[ram storage]
  elsif category != "tv" && chance(0.5)
    title << memory(storage)
    said << "storage"
  end
  if %w[laptop tv].include?(category) && chance(0.8)
    title << "#{inches(diagonal).tr('.', pick(%w[. ,]))}\""
    said << "screen_diagonal"
  end
  if truth["cpu"] && chance(0.6) then title << truth["cpu"]; said << "cpu" end
  if truth["resolution"] && chance(0.7) then title << pick(RESOLUTIONS[truth["resolution"]]); said << "resolution" end
  if chance(noise ? 0.6 : 0.85) then title << pick(COLORS[color]); said << "color" end

  description = [ pick(FLUFF) ]
  if chance(0.6) then description << "#{pick([ 'Диагональ экрана', 'Экран', 'Дисплей с диагональю' ])} #{inches(diagonal).tr('.', ',')} #{pick(%w[дюйма дюймов])}."; said << "screen_diagonal" end
  if truth["battery"] && chance(0.6) then description << "Аккумулятор #{truth['battery'].sub(' мАч', '')} #{pick(%w[мАч mAh])}."; said << "battery" end
  if truth["ram"] && chance(0.4) then description << "Оперативная память #{truth['ram']}, #{pick([ 'встроенная память', 'накопитель SSD' ])} #{truth['storage']}."; said += %w[ram storage] end
  if truth["cpu"] && chance(0.4) then description << "Процессор #{truth['cpu']} справится с любыми задачами."; said << "cpu" end
  if noise && truth["storage"] && chance(0.08) then description << "Также доступна версия на #{memory(storage == 128 ? 256 : 128)}." end
  if noise && chance(0.05) then description << "Совместим с аксессуарами Apple и Samsung." end
  description << pick(FLUFF)

  seller = {}
  truth.each do |name, value|
    next unless chance(noise ? 0.35 : 0.6)

    seller[pick(KEYS[name])] = name == "model" && chance(0.3) ? "#{brand} #{value}" : name == "color" ? pick(COLORS[color]) : name == "screen_diagonal" ? "#{value.delete('"')} дюйм" : value
    said << name
  end
  seller["Страна производства"] = pick(%w[Китай Вьетнам Индия]) if chance(0.5)
  seller["Гарантия"] = "12 мес." if chance(0.4)

  gold = truth.select { |name, _| said.include?(name) || chance(0.03) }
  { "id" => "SKU-#{index.to_s.rjust(6, '0')}", "title" => title.join(" "), "description" => description.join(" "), "seller" => seller,
    "category" => CATEGORY_TITLES[category], "gold" => gold }
end

ATTRIBUTES = KEYS.keys.freeze

def write_csv(path, rows, headers, separator: ",")
  CSV.open(path, "w", col_sep: separator) { |csv| csv << headers; rows.each { |row| csv << row } }
end

dir = ARGV[0] || "data/sample"
FileUtils.mkdir_p(dir)
cards = ->(count, noise:, from: 1) { Array.new(count) { |index| card(from + index, noise: noise) } }

# 1. The plain shape: English headers, attributes as JSON, a gold column per attribute.
[ [ "train.csv", 600, true, 1 ], [ "validation.csv", 250, true, 10_001 ], [ "clean.csv", 200, false, 20_001 ] ].each do |name, count, noise, from|
  write_csv("#{dir}/#{name}", cards.call(count, noise: noise, from: from).map { |c|
    [ c["id"], c["title"], c["description"], JSON.generate(c["seller"]), c["category"], *c["gold"].values_at(*ATTRIBUTES) ]
  }, %w[id title description attributes category] + ATTRIBUTES)
end

# 2. Russian headers, semicolons, attributes as a Python dict, gold_ columns, no category.
write_csv("#{dir}/russian_headers.csv", cards.call(150, noise: true, from: 30_001).map { |c|
  [ c["title"], c["description"], c["seller"].to_s.gsub('"', "'").gsub(" => ", ": "), *c["gold"].values_at(*ATTRIBUTES) ]
}, %w[Название Описание Характеристики] + ATTRIBUTES.map { |name| "gold_#{name}" }, separator: ";")

# 3. JSON Lines, other field names, attributes as "key: value" text, gold packed in one object.
File.write("#{dir}/noisy.jsonl", cards.call(200, noise: true, from: 40_001).map { |c|
  JSON.generate("sku" => c["id"], "name" => c["title"], "text" => c["description"],
                "params" => c["seller"].map { |key, value| "#{key}: #{value}" }.join("; "), "labels" => c["gold"])
}.join("\n") + "\n")

# 4. What a hidden test looks like: a JSON array, attributes as a list of pairs, no gold at all.
File.write("#{dir}/unlabelled.json", JSON.pretty_generate(cards.call(100, noise: true, from: 50_001).map { |c|
  { "id" => c["id"], "title" => c["title"], "description" => c["description"], "category" => c["category"],
    "attributes" => c["seller"].map { |key, value| { "name" => key, "value" => value } } }
}))

# 5. Volume, to time a run. Not kept in the repository.
if (large = ARGV[1].to_i).positive?
  write_csv("#{dir}/large.csv", cards.call(large, noise: true, from: 100_001).map { |c|
    [ c["id"], c["title"], c["description"], JSON.generate(c["seller"]), c["category"] ]
  }, %w[id title description attributes category])
end

puts Dir["#{dir}/*"].sort.map { |path| "#{path}: #{File.foreach(path).count} lines" }
