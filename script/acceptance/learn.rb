# Learn which groups of final values are right often enough to publish without review.
#   LLM_MODE=off GOLD=partial bin/rails runner script/acceptance/learn.rb MODEL_DIR HELDOUT.csv OUTPUT.yml
# HELDOUT must be labelled cards the models in MODEL_DIR did not learn from: what is counted there is how the
# shipped pipeline does on cards it has not seen.
model_dir, input, output = ARGV
abort "Usage: script/acceptance/learn.rb MODEL_DIR HELDOUT.csv OUTPUT.yml" unless model_dir && input && output
ENV["ACCEPTANCE_GROUPS"] = "off"
Extraction.config_root = Pathname(model_dir).expand_path
Extraction.reload!
catalog = Extraction::Catalog.current
evaluation = Evaluation.new(partial: true)

module FinalCandidates
  def call(attributes, candidates, category: nil)
    Thread.current[:final_candidates] = candidates
    super
  end
end
Extraction::Resolver.singleton_class.prepend(FinalCandidates)

pipeline = Extraction::Pipeline.new(confirmed: nil, learning: nil)
counts = Hash.new { |hash, signature| hash[signature] = [ 0, 0 ] }
Dataset.new(input).each do |row|
  result = pipeline.call(row.card)
  candidates = Thread.current[:final_candidates].group_by(&:attribute)
  result.findings.each do |finding|
    gold = row.labels[finding.attribute]
    next if finding.missing? || gold.blank?

    attribute = catalog.attributes.fetch(finding.attribute)
    signature = Extraction::AcceptanceGroups.signature(result.category.name, attribute, finding.value, candidates.fetch(finding.attribute, []))
    counts[signature][0] += 1
    counts[signature][1] += 1 if evaluation.send(:same?, finding, gold, result.category)
  end
end
groups = Extraction::AcceptanceGroups.build(counts)
groups.save(Pathname(output))
Pathname(ENV["COUNTS_OUTPUT"]).write(JSON.pretty_generate(counts)) if ENV["COUNTS_OUTPUT"].present?
puts "#{groups.to_h.size} groups from #{counts.values.sum(&:first)} labelled values"
