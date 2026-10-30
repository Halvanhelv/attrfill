namespace :extraction do
  desc "Run the pipeline over every dataset in a folder and print one line per file: bin/stress [DIR]"
  task :stress, [ :dir ] => :environment do |_, args|
    dir = Pathname(args[:dir] || "data/stress")
    files = dir.children.select { |file| file.extname.match?(/\A\.(csv|tsv|json|jsonl|ndjson)\z/i) && !file.basename.to_s.match?(/\.(gold|train)\./) }.sort
    abort "No files in #{dir}. First run: ruby script/generate_stress.rb" if files.empty?

    puts format("%-40s %6s %6s %6s %6s %7s %6s %6s  %s", "file", "cards", "sec", "F1", "exact", "P acc.", "filled", "review", "weakest / problem")

    files.each do |file|
      base = file.basename.to_s.sub(/\.\w+\z/, "")
      gold = dir.join("#{base}.gold.csv")
      train = dir.glob("#{base}.train.*").first

      line = learning_from(train) do
        evaluation = Evaluation.new
        broken = []
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        Extraction::Runner.new(pipeline: Extraction::Pipeline.new).each(Dataset.new(file, labels: (gold if gold.exist?))) do |row, result|
          evaluation.add(result, row.labels)
          bad = result.findings.reject { |finding| finding.confidence.between?(0, 1) && finding.missing? == finding.value.blank? }
          broken << result.card.id if bad.any? || result.findings.size != result.category.attributes.size
        end

        totals = evaluation.totals
        show = ->(value) { value.nil? ? "—" : format("%.3f", value) }
        format("%-40s %6d %6.1f %6s %6s %7s %6s %6s  %s", base.truncate(40), totals[:cards], Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
               show.(totals[:macro_f1]), show.(totals[:exact]), show.(totals[:accepted_precision]), show.(totals[:coverage]), show.(totals[:review]),
               broken.any? ? "INVARIANTS BROKEN: #{broken.first(3).join(', ')}" : "#{totals[:weakest]}#{' (after bin/learn)' if train}")
      rescue StandardError => error
        format("%-40s ERROR %s: %s", base.truncate(40), error.class, error.message.truncate(90))
      end

      puts line
    end
  end

  # Learns from a train file into a copy of config/, so the try leaves nothing behind.
  def learning_from(train)
    return yield unless train

    original = Extraction.config_root
    Dir.mktmpdir do |copy|
      FileUtils.cp_r("#{original}/.", copy)
      Extraction.config_root = Pathname(copy)
      Extraction.reload!
      Extraction::Learner.new(Dataset.new(train)).call.save!
      yield
    end
  ensure
    Extraction.config_root = original if original
    Extraction.reload!
  end
end
