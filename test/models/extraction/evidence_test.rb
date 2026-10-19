require "test_helper"

class Extraction::EvidenceTest < ActiveSupport::TestCase
  def candidate(source, origin: source, confidence: 0.9)
    Extraction::Candidate.new(attribute: "color", value: "черный", raw: "черный",
                               source: source, origin: origin, confidence: confidence, rule: "test")
  end

  test "reading one title with two algorithms is one piece of evidence" do
    group = [ candidate("title"), candidate("tagger", origin: "title", confidence: 0.85) ]
    assert_in_delta 0.9, Extraction::Resolver.combined(group)
    assert_in_delta 0.99, Extraction::Resolver.combined([ candidate("title"), candidate("seller") ])
  end

  test "two catalogue guesses and an LLM quote cannot multiply confidence" do
    assert_in_delta 0.9, Extraction::Resolver.combined([ candidate("reference"), candidate("prior") ])
    assert_in_delta 0.9, Extraction::Resolver.combined([ candidate("title"), candidate("llm", confidence: 0.99) ])
  end

  test "reader agreement can choose a suggestion without making it publishable" do
    readings = [ candidate("title"), candidate("tagger", origin: "title"),
                candidate("seller", confidence: 0.95).with(value: "белый", raw: "белый") ]
    color = Extraction::Resolver.resolve(Extraction::Catalog.current.attributes.fetch("color"), readings)
    assert_equal "черный", color.value
    assert color.review?
    assert_equal [ "белый" ], color.alternatives
  end

  test "an exact copy of the title in the description adds no confidence" do
    title = "Смартфон Samsung A15 черный"
    alone = extract(title: title)["color"]
    repeated = extract(title: title, description: title)["color"]
    assert_equal alone.confidence, repeated.confidence
  end

  test "a heading borrowed from a description is not a second source" do
    result = extract(title: "", description: "Смартфон Samsung A15 черный. Гарантия 12 месяцев.")
    assert_in_delta 0.9, result["color"].confidence
  end

  test "competing title colors remain visible and need review" do
    color = extract(title: "Смартфон Samsung A15 черный или белый")["color"]
    assert color.review?
    assert_equal %w[белый черный], [ color.value, *color.alternatives ].sort
  end

  test "a color of an accessory or unexplained description is weak evidence" do
    accessory = extract(title: "Смартфон Samsung A15", description: "В комплекте черный чехол")["color"]
    assert accessory.review?
    assert_equal "mention", accessory.rule
    explicit = extract(title: "Смартфон Samsung A15", description: "Цвет корпуса: черный")["color"]
    assert_equal "dictionary", explicit.rule
    assert_operator explicit.confidence, :>, accessory.confidence
  end

  test "a negated color is not the product color" do
    color = extract(title: "Смартфон Samsung A15 не черный, белый")["color"]
    assert_equal "белый", color.value
    assert_empty color.alternatives
  end

  test "the tagger cannot restore a negated color" do
    tagger = Object.new
    def tagger.rule = "fake"
    def tagger.spans(text, **)
      position = text.index("черный")
      position ? [ Extraction::Tagger::Span.new(attribute: "color", raw: "черный", start: position) ] : []
    end
    color = extract(title: "Смартфон Samsung A15 не черный", tagger: tagger)["color"]
    assert color.missing?
  end
end
