# Base for every agent: the model the environment names, asked for the same answer every time.
class ApplicationAgent < RubyLLM::Agent
  PROVIDER = LlmSettings.provider.to_sym
  API_BASE = ENV["LLM_API_BASE"].presence || ENV["OPENAI_BASE_URL"].presence
  GIGASCHOOL = API_BASE&.include?("hub.gigaschool.ru")
  MODEL = ENV["LLM_MODEL"].presence || ENV["OPENAI_MODEL"].presence ||
          (PROVIDER == :anthropic ? "claude-haiku-5-5" : GIGASCHOOL ? "ai-sage/GigaChat3-10B-A1.8B" : "gpt-4o-mini")

  # The endpoint's models are not in RubyLLM's registry, so it is told to take the name as given.
  # OpenAI-compatible gateways commonly expose Chat Completions but not the
  # newer Responses API. Pin that protocol for the case gateway.
  protocol = GIGASCHOOL ? :chat_completions : nil
  model MODEL, provider: PROVIDER, protocol: protocol, assume_model_exists: true
  # Newer Claude models refuse a temperature; they are steady enough without one.
  temperature 0.0 unless PROVIDER == :anthropic
end
