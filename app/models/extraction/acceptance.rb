module Extraction
  # A publication policy, not a promise of measured accuracy. Benchmark and strict
  # modes must be evaluated independently on held-out data.
  module Acceptance
    FILTERS = %w[brand model ram storage screen_diagonal resolution color battery].freeze

    module_function

    def mode = ENV["ACCEPTANCE_MODE"] == "standard" ? "standard" : "strict"

    # Deployment policy must not come from a cached training configuration.
    def policy = @policy ||= YAML.load_file(Rails.root.join("config/acceptance.yml"))

    def policy_version = mode == "strict" ? policy.fetch("version") : "standard"

    def review_required?(name, category: nil)
      return false unless mode == "strict"

      manual = policy.fetch("manual_review")
      manual.fetch("attributes").include?(name) || manual.fetch("categories").include?(category)
    end

    def threshold(attribute)
      mode == "strict" ? [ attribute.threshold, policy.fetch("minimum_confidence") ].max : attribute.threshold
    end

    def allowed?(attribute, candidates, category: nil)
      return false if review_required?(attribute.name, category: category)
      # An LLM quotation proves presence of text, not that the value follows from it.
      supported = candidates.reject { |candidate| candidate.source == "llm" || candidate.origin == "unverified_identity" }
      return false if supported.empty?
      return true unless mode == "strict"

      # The tagger is calibrated on all its readings, most of which a rule confirms; alone it is far weaker
      # (misspelt brands such as "SAMSNUG", a word next to an unknown brand), so a rule must read the value too.
      supported.any? { |candidate| !%w[prior tagger].include?(candidate.source) && candidate.rule != "mention" }
    end
  end
end
