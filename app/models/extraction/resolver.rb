module Extraction
  # Settles each attribute from its candidates: sources that agree raise the confidence,
  # a different value found elsewhere lowers it, and what stays under the threshold goes to review.
  module Resolver
    CONFLICT_PENALTY = 0.25
    # Values that only come from outside the card: the catalogue of known products, the category, a model's answer.
    BORROWED_SOURCES = %w[confirmed reference prior llm].freeze

    module_function

    def call(attributes, candidates, category: nil)
      by_attribute = candidates.group_by(&:attribute)
      attributes.map { |attribute| resolve(attribute, by_attribute.fetch(attribute.name, []), category: category) }
    end

    def resolve(attribute, candidates, category: nil)
      return finding(attribute, status: "missing") if candidates.empty?

      (best, _), *others = readings(attribute, candidates)
      agreeing = candidates.select { |candidate| attribute.kind.same?(best.value, candidate.value) }
      rival = others.map do |candidate, _|
        combined(candidates.select { |reading| attribute.kind.same?(candidate.value, reading.value) })
      end.max.to_f
      confidence = (combined(agreeing) - CONFLICT_PENALTY * rival).clamp(0.01, 0.99).round(2)
      # Brand names in a description are often mere mentions ("works with Apple"), while two different values of a
      # characteristic are a real ambiguity: agreement elsewhere must not push "256 GB" against "128 GB" over the threshold.
      conflict = others.any? && !%w[brand model].include?(attribute.name)
      accepted = !conflict && confidence >= Acceptance.threshold(attribute) &&
                 Acceptance.allowed?(attribute, agreeing, category: category)
      finding(attribute, value: best.value, confidence: confidence, source: best.source, rule: best.rule, raw: best.raw,
              status: accepted ? "accepted" : "review",
              alternatives: others.map { |candidate, _| candidate.value })
    end

    # Candidates that mean the same value, strongest first, each group with its combined score.
    def readings(attribute, candidates)
      groups = candidates.sort_by { |candidate| -candidate.confidence }.each_with_object([]) do |candidate, result|
        group = result.find { |members| attribute.kind.same?(members.first.value, candidate.value) }
        group ? group << candidate : result << [ candidate ]
      end

      # What the card itself says comes before what is only borrowed: a value of another variant of a product whose
      # identity is not confirmed is never the suggestion over the card's own text, and a value written on the card
      # comes before a catalogue one even when the catalogue source calibrated higher on the training sample.
      groups.map do |group|
        representative = group.max_by { |candidate| [ direct?(candidate) ? 1 : 0, candidate.confidence ] }
        [ representative, agreement_score(group), borrowed?(group) ]
      end.sort_by { |candidate, score, borrowed| [ borrowed ? 1 : 0, direct?(candidate) ? 0 : 1, -score ] }
         .map { |candidate, score, _| [ candidate, score ] }
    end

    # The tagger reads the card's text as the rules do.
    def direct?(candidate) = !BORROWED_SOURCES.include?(candidate.source)

    def borrowed?(group) = group.all? { |candidate| candidate.origin == "unverified_identity" }

    # Agreement between readers helps choose a suggestion, even when the readers
    # saw the same text. This ranking heuristic is not publication confidence.
    def agreement_score(group)
      strongest = group.group_by(&:source).values.map { |members| members.map(&:confidence).max }
      1 - strongest.reduce(1.0) { |miss, confidence| miss * (1 - confidence) }
    end

    # Independent sources agreeing: the chance that all of them are wrong at once.
    def combined(group)
      grounded = group.reject { |candidate| candidate.source == "llm" || candidate.origin == "unverified_identity" }
      group = grounded unless grounded.empty?
      strongest = group.group_by { |candidate| evidence_group(candidate) }.values.map { |same_source| same_source.map(&:confidence).max }
      1 - strongest.reduce(1.0) { |miss, confidence| miss * (1 - confidence) }
    end

    # A rule and a tagger reading the same text are one piece of evidence.
    # Catalogue-derived sources are correlated too; neither may multiply an
    # existing reading into certainty. Text repetition is handled by Pipeline.
    def evidence_group(candidate)
      case candidate.source
      when "reference", "prior" then "catalogue"
      when "llm" then "text"
      else candidate.origin
      end
    end

    def finding(attribute, status:, value: nil, confidence: 0.0, source: nil, rule: nil, raw: nil, alternatives: [])
      Finding.new(attribute: attribute.name, title: attribute.label, value: value, confidence: confidence,
                  status: status, source: source, rule: rule, raw: raw, alternatives: alternatives)
    end
  end
end
