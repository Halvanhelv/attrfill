namespace :extraction do
  desc "Learn on TRAIN, then read TEST with each layer combination: bin/compare TRAIN TEST [VARIANTS]"
  task :compare, [ :train, :test, :variants ] => :environment do |_, args|
    train = args.fetch(:train) { abort "usage: bin/compare TRAIN TEST [rules,perceptron,transformer,llm,perceptron+ref+prior+llm,…]" }
    test = args.fetch(:test) { abort "usage: bin/compare TRAIN TEST [VARIANTS]" }
    # bin/compare joins its arguments with commas, so variants after the first arrive as rake's extras.
    variants = [ args[:variants].presence || "rules,perceptron", *args.extras ].join(",").split(/[\s;]+|(?<=\w),(?=\w)/)

    learned(train) do
      taggers = {
        "perceptron" => -> { Extraction::Tagger::Perceptron.load(Extraction.config_path("tagger/perceptron.json.gz")) },
        "transformer" => lambda do
          transformer = Extraction::Tagger::Transformer.load(Rails.root.join(ENV.fetch("TRANSFORMER_DIR", "config/tagger/transformer")))
          transformer.tap { Extraction::Learner.new(Dataset.new(train)).calibrate!(transformer) if transformer }
        end
      }
      rows = Dataset.new(test).to_a
      rows = rows.first(ENV["LIMIT"].to_i) if ENV["LIMIT"]

      puts format("%-24s %6s %6s %6s %7s %6s %6s %7s %7s  %s", "variant", "F1", "F1 traf.", "exact", "P acc.", "filled", "review", "to LLM", "sec", "weakest")
      variants.each do |variant|
        layers = variant.split("+")
        tagger = (layers & taggers.keys).first&.then { |name| taggers.fetch(name).call or abort "no #{name} model" }
        llm = Extraction::LlmFallback.new if layers.include?("llm")
        abort "no LLM_API_KEY" if llm && !Extraction::LlmFallback.enabled?

        evaluation = Evaluation.new
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        reference = Extraction::Reference.current if layers.include?("ref")
        prior = Extraction::Prior.current if layers.include?("prior")
        pipeline = Extraction::Pipeline.new(llm: llm, tagger: tagger, reference: reference, prior: prior)
        Extraction::Runner.new(pipeline: pipeline).each(rows) { |row, result| evaluation.add(result, row.labels) }

        totals = evaluation.totals
        show = ->(value) { value.nil? ? "—" : format("%.3f", value) }
        puts format("%-24s %6s %6s %6s %7s %6s %6s %7s %7.1f  %s", variant, show.(totals[:macro_f1]), show.(totals[:traffic_f1]), show.(totals[:exact]),
                    show.(totals[:accepted_precision]), show.(totals[:coverage]), show.(totals[:review]), llm ? totals[:asked_model] : "—",
                    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, totals[:weakest])
        puts evaluation.to_markdown, "" if ENV["DETAIL"]
        evaluation.segments.each { |segment| puts format("    %-40s %6d vals  F1 %.3f  filled %.3f  review %.3f", *segment.values) } if ENV["SEGMENTS"]
      end
    end
  end
end

# LEARNED=dir keeps what was learned from TRAIN there and reuses it next time: learning a big set takes minutes.
def learned(train, &)
  return learning_from(train, &) unless ENV["LEARNED"]

  dir = Rails.root.join(ENV["LEARNED"])
  unless dir.exist?
    FileUtils.mkdir_p(dir)
    FileUtils.cp_r("#{Extraction.config_root}/.", dir)
    Extraction.config_root = dir
    Extraction.reload!
    Extraction::Learner.new(Dataset.new(train)).call.save!
  end
  Extraction.config_root = dir
  Extraction.reload!
  yield
ensure
  Extraction.config_root = Rails.root.join("config")
  Extraction.reload!
end

namespace :extraction do
  desc "Write tagger training examples as JSON lines (for script/ner/train.py): bin/rails 'extraction:tagger_examples[TRAIN,OUT]'"
  task :tagger_examples, [ :train, :output, :gold ] => :environment do |_, args|
    output = Pathname(args[:output] || "tmp/tagger_examples.jsonl")
    count = 0
    output.open("w") do |file|
      # Held-out cards are left for Learner#calibrate! to measure the trained model on.
      kept = Extraction::Learner.split(Dataset.new(args.fetch(:train), labels: args[:gold]).to_a).last
      Extraction::Tagger::Examples.new(kept).each do |example|
        file.puts(JSON.generate(example.to_h))
        count += 1
      end
    end
    puts "#{count} examples → #{output}"
  end
end

namespace :extraction do
  desc "Measure the transformer on held-out labelled cards: bin/rails 'extraction:calibrate_transformer[TRAIN]'"
  task :calibrate_transformer, [ :train, :gold ] => :environment do |_, args|
    transformer = Extraction::Tagger::Transformer.load(Extraction.config_path("tagger/transformer")) or abort "no config/tagger/transformer"
    learner = Extraction::Learner.new(Dataset.new(args.fetch(:train), labels: args[:gold])).calibrate!(transformer)
    puts "Transformer on held-out cards: #{learner.calibration.map { |key, value| "#{key.split('/').first} #{value}" }.join(', ')}"
  end
end
