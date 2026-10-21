module Extraction
  # Groups of final values held-out cards showed to be right almost always: a laptop's brand read from its title
  # and confirmed by the tagger, a fridge's model read the same way. A value of such a group is published without
  # review even where the strict policy's blanket gates or its single threshold would hold it back.
  #
  # A group is the category, the attribute, which sources agree on the value and whether another value was offered.
  # Learned by script/acceptance/learn.rb on labelled cards the models did not learn from (config/acceptance-groups.yml),
  # and by ReviewLearning from reviewers' decisions; Learning publishes their values.
  # Guesses are never trusted this way: a group must have a reading of the card's own text.
  class AcceptanceGroups
    MIN_LABELLED = 50
    MIN_PRECISION = 0.995
    GUESSES = %w[prior llm].freeze

    def self.load(path)
      new(YAML.load_file(path) || {}) if path.exist?
    end

    # What a final value is grouped by: its category and attribute, the sources that agree on it (a borrowed value
    # whose product identity is unconfirmed marked "?") and whether a rival value was read.
    def self.signature(category, attribute, value, candidates)
      agreeing, rivals = candidates.partition { |candidate| attribute.kind.same?(value, candidate.value) }
      sources = agreeing.map { |candidate| candidate.origin == "unverified_identity" ? "#{candidate.source}?" : candidate.source }.uniq.sort
      [ category, attribute.name, sources.join("+"), rivals.any? ? "rival" : "alone" ].join("/")
    end

    def self.grounded?(signature)
      signature.split("/")[2].to_s.split("+").any? { |source| !source.end_with?("?") && !GUESSES.include?(source) }
    end

    # { signature => [labelled, right] } in: the groups right often enough on enough labelled values.
    def self.build(counts)
      new(counts.select { |signature, (labelled, right)| grounded?(signature) && labelled >= MIN_LABELLED && right >= MIN_PRECISION * labelled }
                .sort.to_h)
    end

    def initialize(groups)
      @groups = groups
    end

    def to_h = @groups

    def save(path) = path.write(to_h.to_yaml)

    def include?(signature) = @groups.key?(signature)
  end
end
