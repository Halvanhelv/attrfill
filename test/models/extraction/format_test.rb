require "test_helper"

class Extraction::FormatTest < ActiveSupport::TestCase
  test "interval and threshold labels are not learned as units" do
    [ '6.6" и более', "3000-5000 мАч", "1000 - 1999 Вт", "200 Вт и выше", "6.6 inches and above" ].each do |label|
      assert_nil Extraction::Format.detect([ label ] * 6), label
    end
  end

  test "atomic values still teach decimal and unit style in mixed labels" do
    labels = [ "3000-5000 мАч" ] * 20 + [ "4500 mAh" ] * 5
    assert_equal({ "suffix" => " mAh" }, Extraction::Format.detect(labels))
    assert_equal({ "suffix" => '"', "decimal" => "," }, Extraction::Format.detect([ '6,7"' ] * 5))
    assert_equal({ "suffix" => " ГБ", "tb_suffix" => " ТБ" }, Extraction::Format.detect([ "256 ГБ" ] * 5 + [ "1 ТБ" ] * 5))
    assert_equal({ "suffix" => " г/м2" }, Extraction::Format.detect([ "80 г/м2" ] * 5))
  end

  test "previously learned interval suffixes cannot corrupt new measurements" do
    previous = Extraction::Format.learned
    Extraction::Format.instance_variable_set(:@learned,
      { "screen_diagonal" => { "suffix" => '" и более' }, "battery" => { "suffix" => "-5000 мАч" } })
    catalog = Extraction::Catalog.current
    diagonal = catalog.attributes.fetch("screen_diagonal").kind
    battery = catalog.attributes.fetch("battery").kind
    assert_equal '6.7"', diagonal.normalize('6.7"')
    assert_equal "4500 мАч", battery.normalize("4500 мАч")
  ensure
    Extraction::Format.instance_variable_set(:@learned, previous)
  end
end
