# One real, grounded extraction through the configured OpenAI-compatible gateway.
abort "LLM is not configured: set LLM_API_KEY or OPENAI_API_KEY" unless Extraction::LlmFallback.enabled?

catalog = Extraction::Catalog.current
category = catalog.categories.fetch("headphones")
attribute = catalog.attributes.fetch("model")
card = Extraction::Card.build(
  title: "Беспроводные наушники Nothing Ear (a), черные",
  category: "headphones"
)
fallback = Extraction::LlmFallback.new(budget: 1)
candidates = fallback.candidates(card, category, [ attribute ])
candidate = candidates.find { |found| found.attribute == "model" }

abort "LLM answered, but no grounded model was parsed" unless candidate&.rule == "grounded"

puts "OK: LLM gateway"
puts "  provider: #{ApplicationAgent::PROVIDER}"
puts "  model: #{ApplicationAgent::MODEL}"
puts "  request count: #{fallback.asked}"
puts "  grounded model: #{candidate.value}"
