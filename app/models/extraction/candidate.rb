module Extraction
  # One reading of an attribute: where it was found, by which rule, how far to trust it.
  Candidate = Data.define(:attribute, :value, :raw, :source, :rule, :confidence, :origin) do
    def initialize(origin: nil, **fields)
      super(**fields, origin: origin || fields.fetch(:source))
    end

    def self.build(attribute:, value:, raw:, source:, rule:, origin: nil)
      new(attribute: attribute, value: value, raw: raw, source: source, rule: rule,
          confidence: Confidence.of(attribute, source, rule), origin: origin)
    end
  end
end
