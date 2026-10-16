module Extraction
  # What the pipeline settled on for one attribute.
  #   evidence: the acceptance group the value belongs to (AcceptanceGroups.signature), so reviewers' decisions can be
  #             counted per group;
  #   note:     "shadow" when a policy learned from reviews would publish it but runs in shadow mode,
  #             "audit" when a publishable value was sent to review as a sample that keeps its group measured.
  Finding = Data.define(:attribute, :title, :value, :confidence, :status, :source, :rule, :raw, :alternatives, :evidence, :note) do
    def initialize(evidence: nil, note: nil, **fields)
      super(evidence: evidence, note: note, **fields)
    end

    def accepted? = status == "accepted"
    def review? = status == "review"
    def missing? = status == "missing"
  end
end
