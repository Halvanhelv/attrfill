require "test_helper"

class Extraction::DictionaryTest < ActiveSupport::TestCase
  test "factored patterns preserve longest aliases, whole words and offsets" do
    dictionary = Extraction::Dictionary.new({ "Red" => [], "Red Line" => [ "Красная линия" ],
                                              "Черный" => [ "черн~" ], "A+B" => [] })
    assert_equal [ "Red Line", "Red Line", 3 ], dictionary.first("xx Red Line Red")
    assert_equal [ "Red Line", "Красная   линия", 0 ], dictionary.first("Красная   линия")
    assert_equal "Черный", dictionary.first("черная")&.first
    assert_equal "A+B", dictionary.first("A+B")&.first
    assert_nil dictionary.first("Redmi")
    assert_equal [ "Red Line", "Red" ], dictionary.scan("Red Line Red").map(&:first)
  end
end
