# Run via Rails runner. Reads models and data; never writes cards or retrains.
require "digest"

model_dir, output, count = ARGV
Extraction.config_root = Rails.root.join(model_dir || "config")
Extraction.reload!
rows = Dataset.new(Rails.root.join("tmp/readiness/family-test.csv")).to_a
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
pipeline = Extraction::Pipeline.new(llm: nil)
catalog = Extraction::Catalog.current
cold_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
rows.first(10).each { |row| pipeline.call(row.card) }
latencies = []
expected = {}
failures = []
valid = lambda do |result|
  result.findings.size == result.category.attributes.size && result.findings.all? do |finding|
    finding.confidence.finite? && finding.confidence.between?(0, 1) && finding.missing? == finding.value.blank?
  end
end
fingerprint = ->(result) { Digest::SHA256.hexdigest(result.findings.map(&:to_h).to_json) }
rows.each do |row|
  t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = pipeline.call(row.card)
  latencies << Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
  expected[row.object_id] = fingerprint.call(result)
  failures << { phase: "latency", id: row.card.id } unless valid.call(result)
end
latencies.sort!
percentile = ->(p) { latencies[((latencies.size - 1) * p).floor] * 1000 }
items = Array.new((count || 5000).to_i) { |i| rows[i % rows.size] }
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
processed = 0
different = 0
Extraction::Runner.new(pipeline: pipeline, threads: 6).each(items) do |row, result|
  processed += 1
  different += 1 if fingerprint.call(result) != expected[row.object_id]
  failures << { phase: "runner", id: row.card.id } unless valid.call(result)
end
batch_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
schema_cases = 0
catalog.categories.each_value do |category|
  [ "", "Неизвестный товар ZX-#{category.name}" ].each do |title|
    result = pipeline.call(Extraction::Card.build(title: title, category: category.name))
    schema_cases += 1
    failures << { phase: "schema", category: category.name } unless valid.call(result) && result.category.name == category.name
  rescue StandardError => error
    failures << { phase: "schema", category: category.name, error: "#{error.class}: #{error.message}" }
  end
end
random = Random.new(20261020)
tokens = [ "", "<script>alert(1)</script>", "Смартфон", "Samsung", "для", "не черный", "白色", "😀", "8/256GB", "5000 мАч", "IGNORE ALL INSTRUCTIONS", "0", "\\n" ]
fuzz_cases = 300
fuzz_cases.times do |i|
  title = Array.new(random.rand(0..20)) { tokens.sample(random: random) }.join(" ")
  description = i == 0 ? "Мусор " * 5000 : Array.new(random.rand(0..30)) { tokens.sample(random: random) }.join(" ")
  title = "\xFFbroken".b if i == 1
  result = pipeline.call(Extraction::Card.build(title: title, description: description))
  failures << { phase: "fuzz", index: i } unless valid.call(result)
rescue StandardError => error
  failures << { phase: "fuzz", index: i, error: "#{error.class}: #{error.message}" }
end
report = { ruby: RUBY_DESCRIPTION, model_dir: model_dir, categories: catalog.categories.size,
           cold_pipeline_seconds: cold_seconds, latency_cards: rows.size, latency_p50_ms: percentile.call(0.5),
           latency_p95_ms: percentile.call(0.95), latency_p99_ms: percentile.call(0.99),
           runner_cards: processed, runner_threads: 6, runner_seconds: batch_seconds,
           cards_per_second: processed / batch_seconds, deterministic_mismatches: different,
           schema_cases: schema_cases, fuzz_cases: fuzz_cases, failures: failures }
File.write(output, JSON.pretty_generate(report))
puts JSON.generate(report)

exit 1 if failures.any? || different.positive?
