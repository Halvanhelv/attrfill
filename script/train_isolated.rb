# Train every learned layer on TRAIN only, in a new model directory, never in config/.
#
#   GOLD=partial bin/rails runner script/train_isolated.rb TRAIN.csv OUT_DIR [CATALOG.yml] [GENERATED_DIR]
#
# GENERATED_DIR: where script/convert/catalog_full.py wrote catalog.full.yml and dictionaries/catalog/ (the whole
# catalog's categories and filter value lists); they are copied in after the learned files are removed.
#
# Copies config/ without anything learned before (calibration, formats, reference, prior, tagger, learned and
# generated dictionaries, generated catalogs), optionally replaces catalog.yml, then runs the learner on TRAIN.
# The directory is then used with CHECKPOINT_MODEL_DIR=OUT_DIR script/checkpoint.rb. Nothing in config/ or the
# database is written.
require "digest"

# A batch on a loaded machine must not lose a card to Rails' 1 s regexp limit; the app keeps its own limit.
Regexp.timeout = Float(ENV.fetch("BATCH_REGEXP_TIMEOUT", "10"))
train, output, catalog, generated = ARGV
abort "usage: script/train_isolated.rb TRAIN.csv OUT_DIR [CATALOG.yml|-] [GENERATED_DIR]" unless train && output
catalog = nil if catalog == "-"
output = Pathname(output).expand_path
abort "Choose a new output directory" if output.exist?

FileUtils.mkdir_p(output)
FileUtils.cp_r("#{Rails.root.join('config')}/.", output)
%w[calibration.yml formats.yml unreliable.yml reference.json.gz prior.json.gz context.json.gz tagger dictionaries/learned dictionaries/catalog
   master.key credentials.yml.enc].each { |path| FileUtils.rm_rf(output.join(path)) }
Dir[output.join("catalog.*.yml")].each { |path| FileUtils.rm_f(path) }
FileUtils.cp(catalog, output.join("catalog.yml")) if catalog
if generated
  FileUtils.cp(File.join(generated, "catalog.full.yml"), output.join("catalog.full.yml"))
  FileUtils.cp_r(File.join(generated, "dictionaries/catalog"), output.join("dictionaries/catalog"))
end

Extraction.config_root = output
Extraction.reload!
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
rows = Dataset.new(train).to_a
Extraction::Learner.new(rows).call.save!

sources = Dir[Rails.root.join("app/models/**/*.rb")].sort.to_h do |path|
  [ Pathname(path).relative_path_from(Rails.root).to_s, Digest::SHA256.file(path).hexdigest ]
end
output.join("audit-training.json").write(JSON.pretty_generate(
  train_sha256: Digest::SHA256.file(train).hexdigest, train_cards: rows.size, partial_gold: ENV["GOLD"] == "partial",
  catalog_sha256: Digest::SHA256.file(output.join("catalog.yml")).hexdigest, source_sha256: sources,
  seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1), trained_at: Time.current.iso8601))
puts "Trained on #{rows.size} cards → #{output}"
