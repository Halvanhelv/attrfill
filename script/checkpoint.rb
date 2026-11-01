# bin/rails runner script/checkpoint.rb INPUT NEW_OUTPUT_DIR
# One complete run with predictions, diagnostics and reproducibility hashes.
require "digest"
require "open3"

input, destination = ARGV
abort "Usage: bin/rails runner script/checkpoint.rb INPUT NEW_OUTPUT_DIR" unless input && destination && ARGV.size == 2
input = Pathname(input).expand_path
output = Pathname(destination).expand_path
abort "Input does not exist: #{input}" unless input.file?
abort "Output directory must be new: #{output}" if output.exist?
# A batch on a loaded machine must not lose a card to Rails' 1 s regexp limit; the app keeps its own limit.
Regexp.timeout = Float(ENV.fetch("BATCH_REGEXP_TIMEOUT", "10"))
abort "Checkpoint runs require LLM_MODE=off" unless ENV["LLM_MODE"] == "off"
if ENV["CHECKPOINT_MODEL_DIR"].present?
  Extraction.config_root = Pathname(ENV.fetch("CHECKPOINT_MODEL_DIR")).expand_path
  abort "Model directory does not exist" unless Extraction.config_root.directory?
  Extraction.reload!
end

# Refuse silently changing inputs or weights during a measurement.
digest = ->(path) { Digest::SHA256.file(path).hexdigest }
code_files = Dir[Rails.root.join("app/models/**/*.rb"), Rails.root.join("script/checkpoint.rb")].sort
model_files = Dir[Extraction.config_root.join("**/*")].select { |path| File.file?(path) }
model_files.reject! { |path| File.basename(path) == "master.key" || File.extname(path) == ".key" }
inputs = ([ input.to_s, Rails.root.join("config/acceptance.yml").to_s ] + code_files + model_files).uniq.sort
before = inputs.to_h { |path| [ path, digest.call(path) ] }
begin
  revision, revision_status = Open3.capture2("git", "rev-parse", "HEAD", chdir: Rails.root, err: File::NULL)
  git_status, status_result = Open3.capture2("git", "status", "--porcelain", chdir: Rails.root, err: File::NULL)
  git_known = revision_status.success? && status_result.success?
rescue Errno::ENOENT
  revision = git_status = nil
  git_known = false
end
output.mkpath
started_at = Time.current.iso8601
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
evaluation = Evaluation.new
statuses = Hash.new(0)
errors = []
cards = 0

Dataset::Writer.open(output.join("predictions.csv")) do |writer|
  Extraction::Runner.new(fail_fast: true).each(Dataset.new(input)) do |row, result|
    writer << result
    evaluation.add(result, row.labels)
    cards += 1
    result.findings.each do |finding|
      statuses[finding.status] += 1
      gold = row.labels[finding.attribute]
      next if gold.blank?
      kind = Extraction::Catalog.current.attributes.fetch(finding.attribute).kind
      next if !finding.missing? && kind.same?(finding.value, kind.normalize(gold) || gold)

      errors << { id: row.card.id, category: result.category.name, attribute: finding.attribute,
                  predicted: finding.value, gold: gold, status: finding.status, source: finding.source } if errors.size < 200
    end
  end
end
abort "Empty input: checkpoint is incomplete" if cards.zero?
changed = before.keys.reject { |path| File.file?(path) && digest.call(path) == before[path] }
abort "Inputs changed during run; checkpoint is incomplete: #{changed.join(', ')}" if changed.any?

report = evaluation.report.merge("totals" => evaluation.totals, "segments" => evaluation.segments,
                                 "all_output_statuses" => statuses, "error_examples_first_200" => errors)
output.join("report.json").write(JSON.pretty_generate(report))
manifest = {
  complete: true, started_at: started_at, finished_at: Time.current.iso8601,
  seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(3),
  cards: cards, git_revision: (git_known ? revision.strip : nil), working_tree_dirty: (git_known ? git_status.present? : nil),
  source_provenance: (git_known ? "git-and-sha256" : "sha256-only archive"),
  ruby: RUBY_DESCRIPTION, acceptance_mode: Extraction::Acceptance.mode,
  acceptance_policy: Extraction::Acceptance.policy_version, llm_mode: "off",
  config_root: Extraction.config_root.to_s, partial_gold: ENV["GOLD"] == "partial",
  runtime_options: ENV.to_h.slice("TAGGER", "REFERENCE", "PRIOR", "CONTEXT", "EXTRACT_THREADS"),
  input_and_source_sha256: before,
  output_sha256: %w[predictions.csv report.json].to_h { |name| [ name, digest.call(output.join(name)) ] },
  scope: "Local diagnostic run; official score, training provenance and absence of leakage are not certified."
}
# This file exists only after a successful complete run.
output.join("manifest.json").write(JSON.pretty_generate(manifest))
puts JSON.pretty_generate(cards: cards, totals: evaluation.totals, output: output.to_s)
