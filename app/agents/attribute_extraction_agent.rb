# Reads one card for the attributes the rules could not settle.
class AttributeExtractionAgent < ApplicationAgent
  instructions { prompt("instructions") }

  # LLM_STRUCTURED=0 for an endpoint that refuses a JSON schema; the instructions ask for the same JSON either way.
  schema AttributeExtractionSchema unless ENV["LLM_STRUCTURED"] == "0" || GIGASCHOOL
end
