require "test_helper"

module Extraction
  class ReferenceTest < ActiveSupport::TestCase
    Row = Data.define(:card, :labels)

    setup do
      rows = %w[синий черный].map do |color|
        Row.new(card(title: "Смартфон Samsung Galaxy A55 8/256 ГБ #{color}"), { "battery" => "5000 мАч", "color" => color })
      end
      @reference = Reference.build(rows, Pipeline.new(llm: nil, tagger: nil, reference: nil))
    end

    test "a new variant of a known product takes what its variants agree on" do
      result = extract(title: "Смартфон Samsung Galaxy A55 8/128 ГБ зеленый", reference: @reference)

      assert_equal "5000 мАч", result["battery"].value
      assert_equal "reference", result["battery"].source
      assert_equal "зеленый", result["color"].value
    end

    test "what the variants disagree on is not offered, and an unknown product gets nothing" do
      assert_nil extract(title: "Смартфон Samsung Galaxy A55", reference: @reference)["color"].value
      assert_nil extract(title: "Смартфон Samsung Galaxy A35 8/256 ГБ", reference: @reference)["battery"].value
    end

    test "a catalogue reading cannot publish facts before product identity is approved" do
      previous = ENV["ACCEPTANCE_MODE"]
      ENV["ACCEPTANCE_MODE"] = "strict"
      # This deliberately confident reference must still require a person.
      reference = Object.new
      def reference.candidates(_key, _category, attributes)
        return [] unless attributes.any? { |attribute| attribute.name == "battery" }
        [ Candidate.new(attribute: "battery", value: "5000 мАч", raw: "5000 мАч",
                       source: "reference", rule: "unanimous", confidence: 0.99) ]
      end
      result = extract(title: "Смартфон Samsung Galaxy A55", reference: reference)
      assert_equal "5000 мАч", result["battery"].value
      assert result["battery"].review?
      assert_equal "identity_pending", result["battery"].rule
    ensure
      ENV["ACCEPTANCE_MODE"] = previous
    end
  end
end
