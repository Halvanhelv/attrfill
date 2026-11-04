# Replay the frozen historical benchmark with the shipped weights, including from a ZIP without Git.
require "rbconfig"
require "digest"

destination = ARGV.sole rescue nil
abort "Usage: bin/rails runner script/f1_replay.rb NEW_OUTPUT_DIR" unless destination
output = Pathname(destination).expand_path
abort "Choose a new output directory" if output.exist?
evidence = Rails.root.join("results/f1-max")
models = evidence.join("models")
input = evidence.join("test.csv")
expected = JSON.parse(evidence.join("summary.json").read)
abort "Test content changed" unless Digest::SHA256.file(input).hexdigest == expected.fetch("test_sha256")
abort "Missing frozen context weights" unless models.join("context.json.gz").file?
output.mkpath
%w[baseline candidate].each do |mode|
  settings = { "LLM_MODE" => "off", "GOLD" => "partial", "ACCEPTANCE_MODE" => "strict",
               "TAGGER" => "perceptron", "CONTEXT" => mode == "baseline" ? "off" : nil,
               "REFERENCE" => nil, "PRIOR" => nil, "CHECKPOINT_MODEL_DIR" => models.to_s }
  command = [ RbConfig.ruby, Rails.root.join("bin/rails").to_s, "runner", "script/checkpoint.rb", input.to_s, output.join(mode).to_s ]
  abort "#{mode} failed; see incomplete output" unless system(settings, *command, chdir: Rails.root)
  actual = JSON.parse(output.join(mode, "report.json").read)
  frozen = JSON.parse(evidence.join(mode, "report.json").read)
  %w[attributes variants all_output_statuses].each do |key|
    abort "#{mode} differs from the frozen result: #{key}" unless actual.fetch(key) == frozen.fetch(key)
  end
end
puts "Both runs exactly reproduce the frozen counts and metric variants. Output: #{output}"
