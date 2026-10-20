module Extraction
  # Learns from a labelled dataset what needs no model: the values a dictionary did not know, the products
  # already met, and how often each rule is right (the confidence a value is given from then on).
  class Learner
    MIN_SEEN = 2
    MIN_READINGS = 20

    # Cards the tagger is learned and measured on: it reads only so many texts anyway (Perceptron::MAX_TEXTS).
    TAGGER_ROWS = 40_000

    MIN_RENAMED = 3
    RENAME_SHARE = 0.6

    attr_reader :learned, :renamed, :formats, :calibration, :tagger, :unreliable

    def initialize(dataset, catalog: Catalog.current)
      @dataset = dataset
      @catalog = catalog
    end

    def call
      rows = @rows = @dataset.to_a
      learn_writing(rows)
      learn_unreliable(rows)

      pipeline = Pipeline.new(catalog: @catalog, llm: nil, prior: nil, unreliable: unreliable)
      readings = counted(rows) { |row| pipeline.candidates(row.card) }

      learn_tagger(rows, readings)
      learn_reference(rows, readings)
      learn_prior(rows, readings)

      @calibration = rates(readings)
      self
    end

    # Every fifth labelled card is held out: a tagger is measured on cards it did not learn from.
    def self.split(rows) = rows.each_with_index.partition { |_, index| (index % 5).zero? }.map { |part| part.map(&:first) }

    # A tagger trained elsewhere (script/ner/train.py, on the kept cards only) measured on the held ones.
    def calibrate!(tagger)
      readings = measure(tagger, Learner.split(@dataset.to_a).first, readings_table)
      @calibration = rates(readings)
      merge_yaml("calibration.yml", calibration)
      Extraction.reload!
      self
    end

    def save!
      save_writing!
      Extraction.config_path("calibration.yml").write(calibration.to_yaml) if calibration.any?
      unreliable&.save(Extraction.config_path("unreliable.yml"))
      tagger&.save(Extraction.config_path("tagger/perceptron.json.gz"))
      # Products are keyed once the brands just learned are known, as they will be when cards are filled.
      Extraction.reload!
      Reference.build(@rows, Pipeline.new(llm: nil, tagger: nil, reference: nil)).save(Extraction.config_path("reference.json.gz")) if @rows
      Prior.build(@rows, Catalog.current).save(Extraction.config_path("prior.json.gz")) if @rows
      Extraction.reload!
    end

    # Each value a rule reads, counted per category against gold before anything is dropped: the ones mostly wrong
    # are what Unreliable drops from then on.
    def learn_unreliable(rows)
      pipeline = Pipeline.new(catalog: @catalog, llm: nil, tagger: nil, reference: nil, prior: nil, context: nil, unreliable: nil)
      parts = Extraction.in_parallel(rows) do |slice|
        slice.each_with_object({}) do |row, part|
          category = @catalog.detect(row.card)
          pipeline.candidates(row.card, category).each do |candidate|
            next unless Unreliable::SOURCES.include?(candidate.source)
            gold = row.labels[candidate.attribute] or next

            kind = @catalog.attributes.fetch(candidate.attribute).kind
            expected = kind.normalize(gold, category: category) || gold
            right = kind.same?(candidate.value, expected)
            values = part[Unreliable.key(category.name, candidate.attribute, candidate.source)] ||= {}
            Unreliable.forms(candidate).each do |form|
              counts = values[form] ||= [ 0, 0, Hash.new(0) ]
              counts[0] += 1
              counts[1] += 1 if right
              counts[2][expected.to_s] += 1
            end
          end
        end
      end
      counts = Hash.new { |hash, key| hash[key] = Hash.new { |values, value| values[value] = [ 0, 0, Hash.new(0) ] } }
      parts.each do |part|
        part.each do |key, values|
          values.each do |value, (total, right, golds)|
            counts[key][value][0] += total
            counts[key][value][1] += right
            golds.each { |gold, seen| counts[key][value][2][gold] += seen }
          end
        end
      end
      @unreliable = Unreliable.build(counts)
    end

    private

    # What the labels show without running anything: values no dictionary has, values a dictionary writes
    # differently from the dataset, and the unit and decimal mark numbers are written with.
    def learn_writing(rows)
      unknown = Hash.new { |hash, dictionary| hash[dictionary] = Hash.new(0) }
      written = Hash.new { |hash, key| hash[key] = Hash.new(0) }
      golds = Hash.new { |hash, name| hash[name] = [] }
      # Built once a dictionary: its pattern takes long to compile.
      known_to = Hash.new { |hash, dictionary| hash[dictionary] = Dictionary.new(Dictionary.entries_for(dictionary)) }

      rows.each do |row|
        row.labels.each do |name, gold|
          attribute = @catalog.attributes[name] or next
          golds[name] << gold
          next unless attribute.kind.is_a?(Kinds::Dictionary)

          dictionary = attribute.options.fetch("dictionary")
          known = known_to[dictionary].normalize(gold)
          # A product line ("Galaxy") learned as a brand would take every Samsung Galaxy from Samsung.
          next if !known && dictionary == "brands" && Dictionary["brand_lines"].normalize(gold)
          next if !known && dictionary == "brands" && Kinds::Brand.junk?(gold)

          known ? written[[ dictionary, known ]][gold] += 1 : unknown[dictionary][gold] += 1
        end
      end

      @learned = unknown.transform_values { |values| values.select { |_, seen| seen >= MIN_SEEN }.keys.sort }.reject { |_, values| values.empty? }
      @renamed = written.each_with_object({}) do |((dictionary, ours), spellings), renamed|
        theirs, seen = spellings.max_by(&:last)
        (renamed[dictionary] ||= {})[ours] = theirs if theirs != ours && seen >= MIN_RENAMED && seen >= RENAME_SHARE * spellings.values.sum
      end
      @formats = golds.each_with_object({}) do |(name, values), formats|
        attribute = @catalog.attributes.fetch(name)
        formats[name] = { "granularity" => "family" } if families?(attribute, values)
        next unless attribute.options["format"]

        style = Format.detect(values) or next
        # No terabytes among the examples: written like the gigabytes are ("GB" → "TB"), or as gigabytes when there is no unit.
        if attribute.options["format"].key?("tb_suffix") && !style.key?("tb_suffix") && style["suffix"] != attribute.options.dig("format", "suffix")
          style["tb_suffix"] = style["suffix"].match?(/[GgГг]/) ? style["suffix"].tr("GgГг", "TtТт") : nil
        end
        style = style.reject { |key, value| Format::DEFAULT.merge(attribute.options["format"])[key] == value }
        formats[name] = style if style.any?
      end
    end

    # The tagger is trusted as much as it is right on cards it did not learn from (every fifth one),
    # counted only where it is used: on what the rules left unsettled. Then it learns from all of them.
    def learn_tagger(rows, readings)
      rows = rows.first(TAGGER_ROWS)
      held, kept = Learner.split(rows)
      return if held.empty? || kept.empty?

      # Examples are built once a card (the slow part) and split the way the cards are.
      examples = Extraction.in_parallel(rows) { |slice| slice.map { |row| Tagger::Examples.new([ row ], catalog: @catalog).each.to_a } }.flatten(1)
      measure(Tagger::Perceptron.train(Learner.split(examples).last.flatten(1)), held, readings)
      @tagger = Tagger::Perceptron.train(examples.flatten(1))
    end

    # Known products are measured the same way: built from the kept cards, tried on the held ones.
    def learn_reference(rows, readings)
      held, kept = Learner.split(rows)
      return if held.empty? || kept.empty?

      reference = Reference.build(kept, Pipeline.new(catalog: @catalog, llm: nil, tagger: nil, reference: nil, unreliable: unreliable))
      trial = Pipeline.new(catalog: @catalog, llm: nil, tagger: nil, reference: reference, prior: nil, unreliable: unreliable)
      counted(held, readings) { |row| trial.referenced_unsettled(row.card) }
    end

    def learn_prior(rows, readings)
      held, kept = Learner.split(rows)
      return if held.empty? || kept.empty?

      trial = Pipeline.new(catalog: @catalog, llm: nil, tagger: nil, reference: nil, prior: Prior.build(kept, @catalog), unreliable: unreliable)
      counted(held, readings) { |row| trial.prior_unsettled(row.card) }
    end

    def measure(tagger, held, readings)
      trial = Pipeline.new(catalog: @catalog, llm: nil, tagger: tagger, prior: nil, unreliable: unreliable)
      counted(held, readings) { |row| trial.tagged_unsettled(row.card) }
    end

    def readings_table = Hash.new { |hash, key| hash[key] = [ 0, 0 ] }

    # How many readings of each rule there were and how many matched gold, counted on every core and added up.
    def counted(rows, readings = readings_table, &read)
      parts = Extraction.in_parallel(rows) do |slice|
        slice.each_with_object({}) do |row, part|
          read.call(row).each do |candidate|
            gold = row.labels[candidate.attribute] or next
            kind = @catalog.attributes.fetch(candidate.attribute).kind
            reading = part["#{candidate.attribute}/#{candidate.source}/#{candidate.rule}"] ||= [ 0, 0 ]
            reading[0] += 1
            # Gold is read for the card's category, as the candidate was (a watch's mm is not a TV's inch).
            expected = kind.normalize(gold, category: @catalog.categories[row.card.category.to_s]) || gold
            reading[1] += 1 if kind.same?(candidate.value, expected)
          end
        end
      end
      parts.each { |part| part.each { |key, (total, correct)| readings[key][0] += total; readings[key][1] += correct } }
      readings
    end

    def rates(readings)
      readings.select { |_, (total, _)| total >= MIN_READINGS }
              .transform_values { |total, correct| ((correct + 1.0) / (total + 2)).round(3) }.sort.to_h
    end

    # Labels that mostly name a processor's family, not the processor.
    def families?(attribute, values)
      return false unless attribute.options["families"]

      values.count { |value| attribute.kind.family(value)&.casecmp?(value.strip) } >= RENAME_SHARE * values.size
    end

    def save_writing!
      learned.each { |dictionary, values| merge_yaml("dictionaries/learned/#{dictionary}.yml", values.to_h { |value| [ value, [] ] }, keep: true) }
      renamed.each { |dictionary, names| merge_yaml("dictionaries/learned/#{dictionary}.names.yml", names) }
      merge_yaml("formats.yml", formats) if formats.any?
    end

    def merge_yaml(file, values, keep: false)
      path = Extraction.config_path(file)
      path.dirname.mkpath
      known = path.exist? ? (YAML.load_file(path) || {}) : {}
      path.write((keep ? values.merge(known) : known.merge(values)).to_yaml)
    end
  end
end
