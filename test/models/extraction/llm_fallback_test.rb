require "test_helper"

class Extraction::LlmFallbackTest < ActiveSupport::TestCase
  TITLE = "Смартфон Kvazar Orbit 5".freeze
  DESCRIPTION = "Корпус цвета морской волны, батарейка на пять тысяч".freeze

  def fallback(agent, **options) = Extraction::LlmFallback.new(agent: agent, **options)

  test "even a valid quote of a compatible device does not name the accessory" do
    agent = FakeAgent.new([ { "name" => "brand", "value" => "Samsung", "quote" => "Samsung Galaxy S24" },
                           { "name" => "model", "value" => "Galaxy S24", "quote" => "Samsung Galaxy S24" } ])
    result = extract(title: "Чехол для смартфона Samsung Galaxy S24", llm: fallback(agent))
    assert result["brand"].missing?
    assert result["model"].missing?
  end

  test "the model is not asked when the rules settled everything" do
    agent = FakeAgent.new
    extract(llm: fallback(agent), title: "Телевизор LG 55UR78006LK 55\" 4K UHD черный")

    assert_empty agent.questions
  end

  test "the model is asked once, only about what is unsettled" do
    agent = FakeAgent.new([ { "name" => "color", "value" => "бирюзовый", "quote" => "цвета морской волны" } ])
    result = extract(llm: fallback(agent), title: TITLE, description: DESCRIPTION, seller_attributes: "Бренд: Kvazar")

    assert_equal 1, agent.questions.size
    assert_includes agent.questions.first, "- color (Color)"
    assert_not_includes agent.questions.first, "- brand"
    assert result.asked_model
    assert_equal [ "бирюзовый", "llm", "grounded" ], result["color"].to_h.values_at(:value, :source, :rule)
  end

  test "a value whose quote is not in the card is not trusted" do
    agent = FakeAgent.new([ { "name" => "battery", "value" => "5000 мАч", "quote" => "аккумулятор 5000 мАч" } ])
    finding = extract(llm: fallback(agent), title: TITLE, description: DESCRIPTION)["battery"]

    assert finding.missing?
  end

  test "a value in the wrong shape and a null are dropped" do
    agent = FakeAgent.new([ { "name" => "battery", "value" => "большая", "quote" => "батарейка" },
                            { "name" => "storage", "value" => nil, "quote" => nil }, { "name" => "weight", "value" => "1 кг" } ])
    result = extract(llm: fallback(agent), title: TITLE, description: DESCRIPTION)

    assert result["battery"].missing?
    assert result["storage"].missing?
  end

  test "the same question is answered from the cache" do
    agent = FakeAgent.new([ { "name" => "color", "value" => "бирюзовый", "quote" => "цвета морской волны" } ])
    llm = fallback(agent)

    2.times { extract(llm: llm, title: TITLE, description: DESCRIPTION) }

    assert_equal 1, agent.questions.size
    assert_equal [ 1, 120, 30 ], [ LlmCall.count, LlmCall.sole.input_tokens, LlmCall.sole.output_tokens ]
  end

  test "the budget stops the asking, not the run" do
    agent = FakeAgent.new
    llm = fallback(agent, budget: 1)

    extract(llm: llm, title: "Смартфон Kvazar A")
    result = extract(llm: llm, title: "Смартфон Kvazar B")

    assert_equal 1, agent.questions.size
    assert result["brand"].present?
  end

  test "an endpoint that keeps failing is left alone and the card still comes out" do
    agent = FakeAgent.new(error: RubyLLM::Error.new)
    llm = fallback(agent)

    results = Array.new(5) { |index| extract(llm: llm, title: "Смартфон Kvazar #{index}") }

    assert_equal Extraction::LlmFallback::FAILURES_TO_REST, agent.questions.size
    assert results.all? { |result| result["color"].missing? }
    assert_equal 0, LlmCall.count
  end

  test "an answer given as text is read all the same" do
    agent = FakeAgent.new
    agent.define_singleton_method(:ask) do |_|
      FakeAgent::Response.new("Вот ответ:\n{\"attributes\": [{\"name\": \"color\", \"value\": \"бирюзовый\", \"quote\": \"цвета морской волны\"}]}", FakeAgent::Tokens.new(1, 1))
    end

    assert_equal "бирюзовый", extract(llm: fallback(agent), title: TITLE, description: DESCRIPTION)["color"].value
  end

  test "the model is asked only about attributes the card speaks of, and always about names" do
    agent = FakeAgent.new
    extract(llm: fallback(agent), title: "Смартфон Kvazar 8/256 ГБ")

    asked = agent.questions.first.scan(/^- (\w+)/).flatten
    assert_includes asked, "brand"
    assert_not_includes asked, "color"
    assert_not_includes asked, "battery"
  end
end
