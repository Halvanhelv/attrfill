require "digest"
require "tmpdir"

namespace :extraction do
  desc "Train in isolation and compare publication policies: extraction:audit[TRAIN,TEST,OUTPUT]"
  task :audit, [ :train, :test, :output ] => :environment do |_, args|
    train = args.fetch(:train)
    test = args.fetch(:test)
    output = Pathname(args[:output] || "tmp/acceptance-audit.json")
    original_root = Extraction.config_root
    original_mode = ENV["ACCEPTANCE_MODE"]
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      Dir.mktmpdir("attrfill-audit") do |dir|
        FileUtils.cp_r("#{original_root}/.", dir)
        Extraction.config_root = Pathname(dir)
        # Never reuse a reference, tagger, learned vocabulary or calibration
        # trained on the full catalogue, which may already contain TEST.
        %w[calibration.yml formats.yml unreliable.yml reference.json.gz prior.json.gz tagger dictionaries/learned dictionaries/catalog].each do |path|
          FileUtils.rm_rf(Extraction.config_path(path))
        end
        Dir[Extraction.config_path("catalog.*.yml")].each { |path| FileUtils.rm_f(path) }
        Extraction.reload!
        train_rows = Dataset.new(train).to_a
        test_rows = Dataset.new(test).to_a
        fingerprint = ->(row) { Digest::SHA256.hexdigest([ row.card.title, row.card.description, row.card.category, row.card.seller_attributes.sort ].to_json) }
        overlap = train_rows.map(&fingerprint).intersection(test_rows.map(&fingerprint))
        if overlap.any?
          test_rows = test_rows.reject { |row| overlap.include?(fingerprint.call(row)) }
          puts "Excluded repeated TEST inputs: #{overlap.size} unique (present in TRAIN)"
        end
        abort "TEST is empty after excluding the overlap" if test_rows.empty?
        supported = Extraction::Catalog.current.categories.values.flat_map { |category| [ category.name, category.title ] }
                              .map { |name| Extraction::Text.key(name) }
        unknown = (train_rows + test_rows).map { |row| row.card.category }.compact.uniq
                                        .reject { |name| supported.include?(Extraction::Text.key(name)) }
        abort "The audit uses the hand-written catalog; unknown categories: #{unknown.join(', ')}" if unknown.any?

        ENV["ACCEPTANCE_MODE"] = "standard"
        puts "Audit: TRAIN #{train_rows.size} cards; TEST #{test_rows.size}"
        source_sha256 = Dir[Rails.root.join("app/models/**/*.rb"), Rails.root.join("lib/tasks/audit.rake"), Rails.root.join("config/catalog.yml"), Rails.root.join("config/acceptance.yml")].sort.to_h do |path|
          [ Pathname(path).relative_path_from(Rails.root).to_s, Digest::SHA256.file(path).hexdigest ]
        end
        cache = Rails.root.join(ENV["AUDIT_MODEL_DIR"]) if ENV["AUDIT_MODEL_DIR"].present?
        training_sha256 = Digest::SHA256.file(train).hexdigest
        reused_training = cache&.exist? || false
        if reused_training
          manifest_path = cache.join("audit-training.json")
          abort "The saved models have no training manifest" unless manifest_path.exist?
          training_manifest = JSON.parse(manifest_path.read)
          abort "TRAIN differs from what the saved models were trained on" unless training_manifest["train_sha256"] == training_sha256
          FileUtils.cp_r("#{cache}/.", dir)
          Extraction.reload!
          puts "Re-measuring on the saved models (no retraining)"
        else
          Extraction::Learner.new(train_rows).call.save!
          training_manifest = { "train_sha256" => training_sha256, "source_sha256" => source_sha256 }
          if cache
            cache.dirname.mkpath
            FileUtils.cp_r(dir, cache)
            cache.join("audit-training.json").write(JSON.pretty_generate(training_manifest))
            puts "Models for re-checking → #{cache}"
          end
        end
        legacy_resolver = Extraction::Resolver.dup
        legacy_resolver.define_singleton_method(:combined) do |group|
          strongest = group.group_by(&:source).values.map { |members| members.map(&:confidence).max }
          1 - strongest.reduce(1.0) { |miss, confidence| miss * (1 - confidence) }
        end
        legacy_config = Extraction::Catalog.config.deep_dup
        legacy_config["attributes"]["color"]["kind"] = "dictionary"
        legacy_catalog = Extraction::Catalog.new(legacy_config)
        reports = %w[standard strict legacy_strict evidence_strict].to_h do |variant|
          legacy = variant == "legacy_strict"
          ENV["ACCEPTANCE_MODE"] = variant == "standard" ? "standard" : "strict"
          catalog = %w[legacy_strict evidence_strict].include?(variant) ? legacy_catalog : Extraction::Catalog.current
          evaluation = Evaluation.new(catalog: catalog)
          errors = []
          puts "Checking: #{variant}"
          pipeline = Extraction::Pipeline.new(llm: nil, catalog: catalog, resolver: legacy ? legacy_resolver : Extraction::Resolver)
          Extraction::Runner.new(pipeline: pipeline).each(test_rows) do |row, result|
            evaluation.add(result, row.labels)
            result.findings.select(&:accepted?).each do |finding|
              gold = row.labels[finding.attribute]
              next if gold.blank?
              kind = catalog.attributes.fetch(finding.attribute).kind
              next if kind.same?(finding.value, kind.normalize(gold) || gold)

              errors << { id: row.card.id, attribute: finding.attribute, value: finding.value, gold: gold,
                          source: finding.source, confidence: finding.confidence } if errors.size < 50
            end
          end
          report = evaluation.report
          report["inference_variant"] = variant
          report["totals"] = evaluation.totals
          report["filter_risk"] = Extraction::Acceptance::FILTERS.to_h do |name|
            counts = report["attributes"][name] || {}
            n = counts.fetch("accepted", 0)
            correct = counts.fetch("accepted_correct", 0)
            lower = Evaluation.precision_lower_bound(correct, n)
            [ name, { accepted: n, errors: n - correct, precision: n.positive? ? correct.to_f / n : nil,
                     precision_lower_95: lower, meets_99_percent_target: lower >= 0.99 } ]
          end
          report["accepted_error_examples"] = errors
          [ variant, report ]
        end
        artifact = { created_at: Time.current.iso8601, train_sha256: Digest::SHA256.file(train).hexdigest,
                     test_sha256: Digest::SHA256.file(test).hexdigest, train_cards: train_rows.size,
                     test_cards: test_rows.size, excluded_identical_inputs: overlap.size, partial_gold: ENV["GOLD"] == "partial",
                     training_acceptance_mode: "standard", source_sha256: source_sha256,
                     reused_training: reused_training, training_source_sha256: training_manifest["source_sha256"],
                     scope: "Manual categories; isolated TRAIN models (fresh or cached as recorded); no LLM; same products may occur in both splits. No claim of new-product generalization.",
                     git_revision: `git rev-parse HEAD`.strip, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
                     reports: reports }
        output.dirname.mkpath
        output.write(JSON.pretty_generate(artifact))
        reports.each { |mode, report| puts "#{mode}: #{report['totals']}" }
        puts "Report → #{output} (contains data samples; do not publish without checking)"
      end
    ensure
      Extraction.config_root = original_root
      ENV["ACCEPTANCE_MODE"] = original_mode
      Extraction.reload!
    end
  end
end
