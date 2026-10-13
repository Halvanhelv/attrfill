# One endpoint, named by the environment: LLM_PROVIDER (openai — any OpenAI-compatible — or anthropic),
# LLM_API_KEY, LLM_API_BASE, LLM_MODEL. Without a key the pipeline runs on rules alone.
# Without LLM_API_KEY, an Anthropic key kept in Rails credentials (anthropic.api_key) is used, and the provider
# defaults to anthropic.
module LlmSettings
  module_function

  def credential = Rails.application.credentials.dig(:anthropic, :api_key).presence

  def provider = ENV["LLM_PROVIDER"].presence || (credential ? "anthropic" : "openai")

  def key = ENV["LLM_API_KEY"].presence || (credential if provider == "anthropic") || ENV["OPENAI_API_KEY"].presence
end

RubyLLM.configure do |config|
  key = LlmSettings.key || ("test-key" if Rails.env.test?)
  base = ENV["LLM_API_BASE"].presence || ENV["OPENAI_BASE_URL"].presence

  if LlmSettings.provider == "anthropic"
    config.anthropic_api_key = key
    config.anthropic_api_base = base if base
  else
    config.openai_api_key = key
    config.openai_api_base = base if base
  end
  config.request_timeout = ENV.fetch("LLM_TIMEOUT", 30).to_i

  # One retry, then the card goes to review: a slow model must not hold a whole run.
  config.max_retries = 1
end
