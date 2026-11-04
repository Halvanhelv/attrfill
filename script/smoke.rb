# A quick production-config check for the demo machine. Unlike tests, this intentionally loads the committed
# perceptron, product reference and category prior. It makes no LLM calls and writes nothing to the database.
pipeline = Extraction::Pipeline.new(llm: nil)

assert = lambda do |condition, message|
  abort "FAIL: #{message}" unless condition
end

simple = pipeline.call(Extraction::Card.build(
  title: "Смартфон Samsung Galaxy S24 Ultra 12/256GB Titanium Black",
  description: "Экран 6.8 дюйма, аккумулятор 5000 мАч"
))
expected = {
  "brand" => "Samsung", "model" => "Galaxy S24 Ultra", "storage" => "256 ГБ", "ram" => "12 ГБ",
  "screen_diagonal" => '6.8"', "battery" => "5000 мАч", "color" => "черный"
}
assert.call(expected.all? { |name, value| simple[name]&.value == value }, "simple smartphone was extracted incorrectly")
assert.call(simple.findings.all?(&:accepted?), "simple smartphone has values requiring review")
assert.call(!simple.asked_model, "simple smartphone unexpectedly called the LLM")

conflict = pipeline.call(Extraction::Card.build(
  title: "Смартфон Samsung Galaxy S24 8/256GB",
  description: "Также доступна версия на 128 ГБ"
))
assert.call(conflict["storage"].review?, "conflicting storage was accepted automatically")
assert.call(conflict["storage"].alternatives.include?("128 ГБ"), "conflicting storage lost its alternative")

accessory = pipeline.call(Extraction::Card.build(
  title: "Чехол для смартфона Samsung Galaxy S24 силиконовый прозрачный"
))
assert.call(accessory.category.name == "generic", "accessory was classified as a device")
assert.call(accessory["brand"].missing? && accessory["model"].missing?, "compatible device was assigned to accessory")

rows = Dataset.new(Rails.root.join("data/sample/edge_cases.csv")).to_a
results = Extraction::Runner.new(pipeline: pipeline).each(rows).to_a
assert.call(results.size == 10, "sample batch did not process all 10 cards")
assert.call(results.none? { |_, result| result.asked_model }, "sample batch unexpectedly called the LLM")

puts "OK: production configuration"
puts "  simple card: 7/7 accepted"
puts "  conflict: review with alternative"
puts "  accessory: compatible device ignored"
puts "  batch: #{results.size}/#{rows.size} cards, 0 LLM calls"
