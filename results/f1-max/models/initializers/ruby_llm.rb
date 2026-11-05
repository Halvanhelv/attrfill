# One endpoint, named by the environment: LLM_PROVIDER (openai — any OpenAI-compatible — or anthropic),
# LLM_API_KEY, LLM_API_BASE, LLM_MODEL. Without a key the pipeline runs on rules alone.
RubyLLM.configure do |config|
  key = ENV["LLM_API_KEY"].presence || ENV["OPENAI_API_KEY"].presence || ("test-key" if Rails.env.test?)
  base = ENV["LLM_API_BASE"].presence || ENV["OPENAI_BASE_URL"].presence

  if ENV["LLM_PROVIDER"] == "anthropic"
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
