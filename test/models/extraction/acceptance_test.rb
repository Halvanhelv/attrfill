require "test_helper"

class Extraction::AcceptanceTest < ActiveSupport::TestCase
  test "missing or misspelled mode cannot weaken publication rules" do
    previous = ENV["ACCEPTANCE_MODE"]
    [ nil, "strcit" ].each do |mode|
      ENV["ACCEPTANCE_MODE"] = mode
      assert_equal "strict", Extraction::Acceptance.mode
    end
  ensure
    ENV["ACCEPTANCE_MODE"] = previous
  end

  def finding(source:, confidence:, mode: "strict")
    previous = ENV["ACCEPTANCE_MODE"]
    ENV["ACCEPTANCE_MODE"] = mode
    attribute = Extraction::Catalog.current.attributes.fetch("brand")
    candidate = Extraction::Candidate.new(attribute: "brand", value: "Samsung", raw: "Samsung",
                                          source: source, rule: "test", confidence: confidence)
    Extraction::Resolver.resolve(attribute, [ candidate ])
  ensure
    ENV["ACCEPTANCE_MODE"] = previous
  end

  test "popular filters require a higher score in strict mode" do
    assert finding(source: "title", confidence: 0.95).review?
    assert finding(source: "title", confidence: 0.99).accepted?
    assert finding(source: "title", confidence: 0.95, mode: "standard").accepted?
  end

  test "a value only the tagger read is not published without a rule reading it too" do
    assert finding(source: "tagger", confidence: 0.99).review?
    assert finding(source: "tagger", confidence: 0.99, mode: "standard").accepted?
  end

  test "category majority cannot publish a filter by itself" do
    assert finding(source: "prior", confidence: 0.99).review?
  end

  test "weak fields and categories require review even at a high score" do
    previous = ENV["ACCEPTANCE_MODE"]
    ENV["ACCEPTANCE_MODE"] = "strict"
    assert Extraction::Acceptance.review_required?("color", category: "smartphone")
    assert Extraction::Acceptance.review_required?("model", category: "tv")
    assert Extraction::Acceptance.review_required?("brand", category: "laptop")
    assert Extraction::Acceptance.review_required?("brand", category: "generic")
    assert_not Extraction::Acceptance.review_required?("brand", category: "tv")
    attribute = Extraction::Catalog.current.attributes.fetch("brand")
    candidate = Extraction::Candidate.new(attribute: "brand", value: "Samsung", raw: "Samsung",
                                          source: "title", rule: "dictionary", confidence: 0.99)
    assert Extraction::Resolver.resolve(attribute, [ candidate ], category: "laptop").review?
    assert Extraction::Resolver.resolve(attribute, [ candidate ], category: "tv").accepted?
    assert_operator Extraction::Acceptance.threshold(Extraction::Catalog.current.attributes.fetch("power")), :>=, 0.98
  ensure
    ENV["ACCEPTANCE_MODE"] = previous
  end

  test "even a very confident LLM cannot publish by itself" do
    assert finding(source: "llm", confidence: 0.99, mode: "standard").review?
  end

  test "LLM requires explicit opt in as well as a key" do
    previous = ENV.to_h.slice("LLM_API_KEY", "LLM_MODE")
    ENV["LLM_API_KEY"] = "test-key"
    ENV.delete("LLM_MODE")
    assert_not Extraction::LlmFallback.enabled?
    ENV["LLM_MODE"] = "on"
    assert Extraction::LlmFallback.enabled?
  ensure
    %w[LLM_API_KEY LLM_MODE].each { |key| ENV[key] = previous[key] }
  end
end
