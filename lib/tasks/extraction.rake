namespace :extraction do
  desc "Extract attributes: bin/rails 'extraction:run[data/cards.csv,data/predictions.csv]'"
  task :run, [ :input, :output, :gold ] => :environment do |_, args|
    input = args.fetch(:input) { abort "usage: bin/extract INPUT [OUTPUT] [GOLD]" }
    output = args[:output] || "data/predictions.csv"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    evaluation = Evaluation.new
    cards = labelled = 0

    Dataset::Writer.open(output) do |writer|
      Extraction::Runner.new.each(Dataset.new(input, labels: args[:gold])) do |row, result|
        writer << result
        evaluation.add(result, row.labels)
        cards += 1
        labelled += 1 if row.labels.any?
      end
    end

    seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
    asked = Extraction::LlmFallback.default&.asked.to_i
    puts "#{cards} cards in #{seconds} s → #{output}. Model requests: #{asked}" \
         "#{' (model off: no LLM_API_KEY)' unless Extraction::LlmFallback.enabled?}"

    next if labelled.zero?

    evaluation.save!
    puts "", evaluation.to_markdown
  end

  desc "Learn dictionaries and confidence from labelled data: bin/rails 'extraction:learn[data/train.csv]'"
  task :learn, [ :input, :gold ] => :environment do |_, args|
    # TRAIN+storage/reviewed.jsonl learns from the dataset and from what reviewers settled (extraction:feedback).
    inputs = args.fetch(:input) { abort "usage: bin/learn TRAIN [GOLD]" }.split("+")
    learner = Extraction::Learner.new(inputs.flat_map { |input| Dataset.new(input, labels: (args[:gold] if input == inputs.first)).to_a }).call
    learner.save!

    learner.learned.each { |dictionary, values| puts "#{dictionary}: #{values.size} new values (#{values.first(8).join(', ')})" }
    learner.renamed.each { |dictionary, names| puts "#{dictionary}: written as the labels write them — #{names.first(8).map { |ours, theirs| "#{ours} → #{theirs}" }.join(', ')}" }
    learner.formats.each { |name, style| puts "#{name}: format as in the labels — #{style.inspect}" }
    puts "Rules with measured confidence: #{learner.calibration.size} → config/calibration.yml"
    tagged = learner.calibration.select { |key, _| key.include?("/tagger/") }
    puts "Tagger → config/tagger/perceptron.json.gz; precision on held-out cards: " \
         "#{tagged.map { |key, value| "#{key.split('/').first} #{value}" }.join(', ').presence || 'too little data'}" if learner.tagger
  end

  desc "Write what reviewers approved or corrected as labelled cards: bin/rails 'extraction:feedback[storage/reviewed.jsonl]'"
  task :feedback, [ :output ] => :environment do |_, args|
    output = Pathname(args[:output] || "storage/reviewed.jsonl")
    count = 0
    output.open("w") do |file|
      reviewed = AttributeValue.where(status: %w[approved corrected]).select(:card_id)
      Card.where(id: reviewed).includes(:attribute_values).find_each do |card|
        labels = card.attribute_values.select { |value| value.approved? || value.corrected? }.to_h { |value| [ value.name, value.value ] }
        file.puts(JSON.generate(id: card.external_id || card.id, title: card.title, description: card.description,
                                category: card.category, seller_attributes: card.seller_attributes, labels: labels))
        count += 1
      end
    end
    puts "#{count} reviewed cards → #{output}. To learn together with the data: bin/learn data/train.csv+#{output}"
  end

  desc "Learn from reviewers' decisions: groups to trust and values confirmed per title (also nightly, LearnFromReviewsJob)"
  task learn_from_reviews: :environment do
    summary = Extraction::ReviewLearning.call
    shadow_n, shadow_right = summary.shadow
    audit_n, audit_right = summary.audit
    puts "Reviewer decisions: #{summary.decisions}; groups learned: #{summary.groups_learned}; titles with confirmed values: #{summary.confirmed_titles}"
    puts "Shadow mode: checked #{shadow_n}, correct #{shadow_right}#{format(' (%.1f%%)', 100.0 * shadow_right / shadow_n) if shadow_n.positive?}"
    puts "Audit of auto-accepted values: checked #{audit_n}, correct #{audit_right}#{format(' (%.1f%%)', 100.0 * audit_right / audit_n) if audit_n.positive?}"
  end

  desc "Compare two predictions files for drift: bin/rails 'extraction:drift[results/predictions_test.csv,data/predictions.csv]'"
  task :drift, [ :before, :after ] => :environment do |_, args|
    drift = Drift.new(args.fetch(:before) { abort "usage: extraction:drift[BEFORE,AFTER]" }, args.fetch(:after))
    names = { filled: "filled", review: "to review", confidence: "confidence", share: "card share" }
    changes = drift.changes
    puts changes.empty? ? "No shifts of #{Drift::THRESHOLD} or more." : "Shifts of #{Drift::THRESHOLD} or more:"
    changes.first(30).each { |change| puts format("  %-40s %-14s %.3f → %.3f", change.subject, names[change.measure], change.before, change.after) }
    puts "New fields: #{drift.new_fields.join(', ')}" if drift.new_fields.any?
  end

  desc "Write docs/eda.md for a dataset: bin/rails 'extraction:eda[data/cards.csv]'"
  task :eda, [ :input ] => :environment do |_, args|
    path = Rails.root.join("docs/eda.md")
    path.write(Dataset::Profile.new(Dataset.new(args.fetch(:input) { abort "usage: bin/eda INPUT" })).to_markdown + "\n")
    puts "→ #{path.relative_path_from(Rails.root)}"
  end
end

namespace :extraction do
  desc "Show where predictions differ from gold: bin/errors INPUT [ATTRIBUTE] [GOLD]"
  task :errors, [ :input, :attribute, :gold ] => :environment do |_, args|
    catalog = Extraction::Catalog.current
    shown = 0

    Extraction::Runner.new.each(Dataset.new(args.fetch(:input) { abort "usage: bin/errors INPUT [ATTRIBUTE] [GOLD]" }, labels: args[:gold])) do |row, result|
      result.findings.each do |finding|
        gold = row.labels[finding.attribute]
        next if args[:attribute].present? && finding.attribute != args[:attribute]
        next if gold.blank? && finding.missing?

        kind = catalog.attributes.fetch(finding.attribute).kind
        next if gold.present? && !finding.missing? && kind.same?(finding.value, kind.normalize(gold) || gold)
        next if (shown += 1) > 40

        puts "#{finding.attribute}: got #{finding.value.inspect} (#{finding.confidence} #{finding.status} #{finding.source}/#{finding.rule}), labelled #{gold.inspect}",
             "    #{result.card.title.truncate(110)} | #{result.card.description.truncate(110)} | #{result.card.seller_text.truncate(80)}"
      end
    end

    puts "Differences: #{shown}#{' (first 40 shown)' if shown > 40}"
  end
end
