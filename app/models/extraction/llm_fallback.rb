module Extraction
  # Asks a model about the attributes the rules left missing or doubtful: one request per card, never twice
  # for the same question, never past the run's budget, and not at all while the endpoint keeps failing.
  class LlmFallback
    FAILURES_TO_REST = 3
    REST = 5.minutes
    DESCRIPTION_LIMIT = 2_000

    FAILURES = [ RubyLLM::Error, Faraday::Error, Timeout::Error, JSON::ParserError ].freeze

    # The case VM exports OPENAI_API_KEY for everyone: a paid call still needs LLM_MODE=on set on purpose.
    def self.enabled? = LlmSettings.key.present? && ENV["LLM_MODE"] == "on"

    def self.default
      return unless enabled?

      @default ||= new
    end

    attr_reader :asked

    def initialize(agent: AttributeExtractionAgent, budget: ENV.fetch("LLM_MAX_CALLS", 2_000).to_i)
      @agent = agent
      @budget = budget
      @asked = 0
      @failures = 0
      @lock = Mutex.new
    end

    def candidates(card, category, attributes)
      question = RubyLLM.render_prompt("attribute_extraction_agent/question", card: card, category: category,
                                       attributes: attributes, description_limit: DESCRIPTION_LIMIT,
                                       hints: attributes.to_h { |attribute| [ attribute.name, attribute.kind.hint ] })

      answer_to(question).filter_map { |item| candidate(item, card, category, attributes) }
    end

    private

    attr_reader :agent

    def answer_to(question)
      key = Digest::SHA256.hexdigest("#{ApplicationAgent::MODEL}\n#{question}")

      ActiveRecord::Base.connection_pool.with_connection do
        LlmCall.find_by(key: key)&.answer || ask(key, question) || []
      end
    end

    def ask(key, question)
      return unless spend!

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = agent.new.ask(question)
      answer = items(response)
      succeeded!

      LlmCall.create_or_find_by!(key: key) do |call|
        call.assign_attributes(model: ApplicationAgent::MODEL, question: question, answer: answer,
                               input_tokens: response.tokens&.input, output_tokens: response.tokens&.output,
                               duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
      end

      answer
    rescue *FAILURES => error
      failed!(error)
      nil
    end

    # The schema's parsed answer, or the JSON found in plain text when the endpoint ignored the schema.
    def items(response)
      content = response.content
      content = JSON.parse(content[/\{.*\}/m] || "{}") if content.is_a?(String)

      Array(content.to_h.deep_stringify_keys["attributes"]).select { |item| item.is_a?(Hash) }
    end

    # A value counts as grounded only when its quote is really in the card: that is the check against invention.
    def candidate(item, card, category, attributes)
      attribute = attributes.find { |one| one.name == item["name"] } or return
      raw = item["value"].to_s.strip
      return if raw.blank? || raw.casecmp?("null")
      return if Reference::NAMING.include?(attribute.name) && Text.only_compatibility_mentions?(card.text, raw)

      value = attribute.kind.normalize(raw, category: category) || (raw if attribute.kind.open?) or return
      return unless quoted?(card, item["quote"])

      rule = "grounded"

      Candidate.build(attribute: attribute.name, value: value, raw: item["quote"].presence || raw, source: "llm", rule: rule)
    end

    def quoted?(card, quote)
      quote = bare(quote)
      quote.length >= 2 && bare(card.text).include?(quote)
    end

    def bare(text) = Text.key(text).gsub(/[^\p{L}\p{N}]/, "")

    def spend!
      @lock.synchronize do
        next false if @asked >= @budget || resting?

        @asked += 1
        true
      end
    end

    def resting? = @rest_until.present? && Time.current < @rest_until

    def succeeded! = @lock.synchronize { @failures = 0 }

    def failed!(error)
      Rails.logger.warn("[LlmFallback] #{error.class}: #{error.message.to_s.truncate(200)}")

      @lock.synchronize do
        @failures += 1
        @rest_until = REST.from_now if @failures >= FAILURES_TO_REST
      end
    end
  end
end
