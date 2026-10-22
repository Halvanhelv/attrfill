require "test_helper"

# Wrong values the independent review (docs/independent-review.md) found accepted without a person.
class AuditRegressionsTest < ActiveSupport::TestCase
  test "words sellers put in the brand field are not learned or read as brands" do
    %w[Sim Wireless Gb 2K HOME Orange Green RED MAX Mi ### #N/A . 1093 E].each { |junk| assert Extraction::Kinds::Brand.junk?(junk), junk }
    %w[LG HP WD BQ Hi Nokia JBL Xiaomi].each { |brand| assert_not Extraction::Kinds::Brand.junk?(brand), brand }

    with_learned_brands("Sim" => [], "Wireless" => [], "Orange" => [], "Kvazar" => []) do
      assert_equal "Nokia", extract(title: "Мобильный телефон 2 SIM Nokia 105")["brand"].value
      assert_equal "JBL", extract(title: "Наушники Wireless JBL Tune 520BT")["brand"].value
      assert_equal "Samsung", extract(title: "Смартфон Orange Samsung Galaxy A15")["brand"].value
      assert_equal "Kvazar", extract(title: "Смартфон Kvazar K7 4/64 ГБ")["brand"].value
    end
  end

  test "a resolution spoken of as content or video is not the screen's" do
    upscaled = extract(title: "Телевизор Samsung UE55AU7100U", description: "Воспроизводит HD-контент с улучшением до 4K.")
    assert upscaled["resolution"].review?
    assert_equal "mention", upscaled["resolution"].rule

    named = extract(title: "Телевизор Samsung UE43T5300AU", description: "Поддержка 4K-контента. Разрешение экрана Full HD.")
    assert_includes [ "Full HD", "1920x1080" ], named["resolution"].value

    ports = extract(title: "Монитор Samsung S27", description: "HDMI до 7680x4320, матрица 3840x2160")
    assert_includes [ "4K UHD", "3840x2160" ], ports["resolution"].value
  end

  test "an accessory named first gets no fields of the device it fits" do
    [ "Чехол на Samsung Galaxy S24 Ultra 12/256 ГБ", "Защитное стекло Samsung Galaxy S24 Ultra", "Пульт к телевизору Samsung UE43",
      "Подставка под монитор Samsung 27\"" ].each do |title|
      result = extract(title: title)
      assert_equal "generic", result.category.name, title
      assert_nil result["storage"], title
    end
    assert_nil extract(title: "Чехол на Samsung Galaxy S24")["brand"].value
    assert_equal "headphones", extract(title: "Наушники с зарядным кейсом JBL Tune 230NC").category.name
  end

  test "a compared brand, a gift and virtual memory are not the product's" do
    assert_not_equal "Samsung", extract(title: "Смартфон Oukitel C36 как Samsung")["brand"].value
    assert_not_equal "10000 мАч", extract(title: "Смартфон Samsung Galaxy A15 4/128 ГБ + Power Bank 10000 мАч в подарок")["battery"].value
    assert_equal "256 ГБ", extract(title: "Планшет Apple iPad Air 11 Wi-Fi + Cellular 256 ГБ")["storage"].value

    ram = extract(title: "Смартфон Infinix Hot 40i 16 ГБ RAM (8+8) 256 ГБ")["ram"]
    assert ram.review?
    assert_includes [ ram.value, *ram.alternatives ], "8 ГБ"
  end

  test "a description that copies the title is not a second source" do
    copied = extract(title: "Смартфон Samsung Galaxy A15 6.5\"", description: "Смартфон Samsung Galaxy A15 6.5\". Хороший смартфон.")
    alone = extract(title: "Смартфон Samsung Galaxy A15 6.5\"")
    assert_equal alone["screen_diagonal"].confidence, copied["screen_diagonal"].confidence
  end

  test "a phone's model name is not an Apple chip" do
    cpu = Extraction::Catalog.current.attributes["cpu"].kind
    read = ->(title) { cpu.scan(title, category: nil, source: "title").map(&:value) }
    assert_empty read.("Смартфон Xiaomi POCO M5 4/64 ГБ")
    assert_empty read.("Смартфон Samsung Galaxy M54")
    assert_equal [ "M2" ], read.("Ноутбук Apple MacBook Air 13 M2 8/256")
  end

  test "seller values in other units are not read as gigabytes or inches" do
    catalog = Extraction::Catalog.current
    assert_nil catalog.attributes["storage"].kind.normalize("4 МБ")
    assert_nil catalog.attributes["screen_diagonal"].kind.normalize("108 см", category: catalog.categories["tv"])
    assert_equal "1.43\"", catalog.attributes["screen_diagonal"].kind.normalize("AMOLED 2.5D, 1.43\"", category: catalog.categories["smartwatch"])
  end

  private

  def with_learned_brands(entries)
    previous = Extraction.config_root
    Dir.mktmpdir("learned-brands") do |dir|
      FileUtils.cp_r("#{previous}/.", dir)
      FileUtils.mkdir_p(File.join(dir, "dictionaries/learned"))
      File.write(File.join(dir, "dictionaries/learned/brands.yml"), entries.to_yaml)
      Extraction.config_root = Pathname(dir)
      Extraction.reload!
      yield
    ensure
      Extraction.config_root = previous
      Extraction.reload!
    end
  end
end
