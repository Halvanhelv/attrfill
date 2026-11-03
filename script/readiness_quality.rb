# Deeper evaluation of the frozen family holdout. No training or model writes.
require "zlib"
require "set"
Extraction.config_root = Rails.root.join("tmp/readiness/family-models")
Extraction.reload!
rows = Dataset.new(Rails.root.join("tmp/readiness/family-test.csv")).to_a
pipeline = Extraction::Pipeline.new(llm: nil)
without_reference = Extraction::Pipeline.new(llm: nil, reference: nil)
known = JSON.parse(Zlib.gunzip(Extraction.config_path("reference.json.gz").binread)).keys.to_set
categories = Hash.new { |hash, name| hash[name] = Evaluation.new(partial: true) }
sources = Hash.new { |hash, name| hash[name] = { accepted: 0, correct: 0 } }
evaluation = Evaluation.new(partial: true)
no_reference = Evaluation.new(partial: true)
known_cards = 0
resolved_known_cards = 0
unseen_lookup = Evaluation.new(partial: true)
calibration = Hash.new { |hash, name| hash[name] = { values: 0, correct: 0 } }
rows.each do |row|
  result = pipeline.call(row.card)
  evaluation.add(result, row.labels)
  categories[result.category.title].add(result, row.labels)
  unreferenced = without_reference.call(row.card)
  no_reference.add(unreferenced, row.labels)
  lookup_key = Extraction::Reference.key(unreferenced["brand"]&.value, unreferenced["model"]&.value)
  if known.include?(lookup_key)
    resolved_known_cards += 1
  else
    unseen_lookup.add(result, row.labels)
  end
  known_cards += 1 if known.include?(pipeline.product_key(row.card))
  result.findings.select(&:accepted?).each do |finding|
    gold = row.labels[finding.attribute]
    next if gold.blank?
    kind = Extraction::Catalog.current.attributes.fetch(finding.attribute).kind
    correct = kind.same?(finding.value, kind.normalize(gold) || gold)
    sources[finding.source][:accepted] += 1
    sources[finding.source][:correct] += 1 if correct
    bucket = finding.confidence >= 0.98 ? "0.98–0.99" : "below 0.98"
    calibration[bucket][:values] += 1
    calibration[bucket][:correct] += 1 if correct
  end
end
report = { categories: categories.transform_values(&:totals), accepted_by_source: sources,
           lookup_keys_seen_in_training_cards: known_cards, lookup_reference_size: known.size,
           resolved_lookup_keys_seen_cards: resolved_known_cards, unseen_resolved_lookup: unseen_lookup.totals,
           with_reference: evaluation.totals, without_reference: no_reference.totals,
           accepted_calibration: calibration }
File.write(Rails.root.join("tmp/readiness/quality-detail.json"), JSON.pretty_generate(report))
puts JSON.generate(report)
