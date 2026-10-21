require "test_helper"

module Extraction
  class PriorTest < ActiveSupport::TestCase
    setup do
      rows = [ %w[зеленый 5000], %w[зеленый 4000], %w[черный 3000] ].map do |color, battery|
        Dataset::Row.new(card: card(title: "Смартфон Samsung Galaxy A55"), labels: { "color" => color, "battery" => "#{battery} мАч" })
      end
      @prior = Prior.build(rows, Catalog.current)
    end

    test "fills an attribute nothing was read for with what most cards of the category say" do
      result = extract(title: "Смартфон Xiaomi Redmi 13", prior: @prior)

      assert_equal "зеленый", result["color"].value
      assert_equal "prior", result["color"].source
      assert_equal "review", result["color"].status
    end

    test "offers nothing without a majority and leaves read values alone" do
      result = extract(title: "Смартфон Xiaomi Redmi 13 черный", prior: @prior)

      assert_nil result["battery"].value
      assert_equal "черный", result["color"].value
    end
  end
end
