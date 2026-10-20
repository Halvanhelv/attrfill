# Per-attribute precision, recall and F1 against gold labels, with how much is filled, how much was accepted
# without a person, and whether the confidence means what it says.
class Evaluation
  PATH = Rails.root.join("storage/metrics.json")
  BUCKETS = [ 0.0, 0.5, 0.7, 0.8, 0.9, 0.95 ].freeze

  Counts = Struct.new(:cards, :gold, :predicted, :correct, :exact, :accepted, :accepted_correct, :review, :missing) do
    def precision = ratio(correct, predicted)
    def recall = ratio(correct, gold)
    def f1 = precision + recall > 0 ? (2 * precision * recall / (precision + recall)).round(4) : 0.0
    def coverage = ratio(predicted, cards)
    def accepted_precision = ratio(accepted_correct, accepted)
    def review_share = ratio(review, cards)

    def ratio(part, whole) = whole.to_i.zero? ? 0.0 : (part.to_f / whole).round(4)

    def to_h
      super.merge(precision: precision, recall: recall, f1: f1, coverage: coverage,
                  accepted_precision: accepted_precision, review_share: review_share)
    end
  end

  def self.last = PATH.exist? ? JSON.parse(PATH.read) : nil

  # How often shoppers' queries name each attribute (script/convert/traffic.py): the fields people search by weigh more.
  def self.traffic
    path = Rails.root.join("config/traffic.yml")
    path.exist? ? (YAML.load_file(path) || {}) : {}
  end

  # partial: the labels list only some attributes of a card (sellers' characteristics); the rest are unknown, not empty.
  def initialize(catalog: Extraction::Catalog.current, partial: ENV["GOLD"] == "partial")
    @catalog = catalog
    @partial = partial
    @counts = Hash.new { |hash, name| hash[name] = Counts.new(0, 0, 0, 0, 0, 0, 0, 0, 0) }
    @segments = Hash.new { |hash, name| hash[name] = Counts.new(0, 0, 0, 0, 0, 0, 0, 0, 0) }
    @buckets = Hash.new { |hash, floor| hash[floor] = [ 0, 0 ] }
    # Labels of attributes the card's category does not extract: misses the main score does not see.
    @out_of_scope = Hash.new(0)
    # Values inside a gold range ("от 15 до 16.9", "3000-5000 мАч") that the main score counts wrong.
    @in_range = Hash.new(0)
    @cards = 0
    @asked_model = 0
  end

  # Only attributes that have a gold column anywhere are scored.
  def add(result, labels)
    @cards += 1
    @asked_model += 1 if result.asked_model

    result.findings.each do |finding|
      gold = labels[finding.attribute]
      next if @partial && gold.blank?

      correct = gold.present? && !finding.missing? && same?(finding, gold, result.category)
      @in_range[finding.attribute] += 1 if !correct && gold.present? && !finding.missing? && GoldRange.inside?(finding, gold, @catalog)
      # The same counts by category: no group of products may be served much worse than the rest.
      [ @counts[finding.attribute], @segments[result.category.label] ].each do |counts|
        counts.cards += 1
        counts.gold += 1 if gold.present?
        counts.predicted += 1 unless finding.missing?
        counts.correct += 1 if correct
        counts.exact += 1 if correct && finding.value.to_s == gold.to_s.strip
        counts.accepted += 1 if finding.accepted?
        counts.accepted_correct += 1 if finding.accepted? && correct
        counts.review += 1 if finding.review?
        counts.missing += 1 if finding.missing?
      end

      next if finding.missing?

      bucket = @buckets[BUCKETS.reverse.find { |floor| finding.confidence >= floor }]
      bucket[0] += 1
      bucket[1] += 1 if correct
    end

    extracted = result.findings.map(&:attribute)
    labels.each do |name, gold|
      @out_of_scope[name] += 1 if gold.present? && @catalog.attributes.key?(name) && !extracted.include?(name)
    end
  end

  # The main score is over the attributes each category extracts. These say what it leaves out, on the same values:
  # all_labels counts the labels of attributes outside the category's list as misses; range_aware credits a number
  # inside a gold range. Neither changes a prediction; they are other ways to read the same run.
  def variants
    names = (@counts.select { |_, counts| counts.gold.positive? }.keys | @out_of_scope.keys)
    f1 = lambda do |name, scope:, range:|
      counts = @counts[name]
      correct = counts.correct + (range ? @in_range[name] : 0)
      gold = counts.gold + (scope ? @out_of_scope[name] : 0)
      precision = counts.predicted.zero? ? 0.0 : correct.to_f / counts.predicted
      recall = gold.zero? ? 0.0 : correct.to_f / gold
      precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0.0
    end
    macro = lambda do |scope:, range:|
      scored = scope ? names : names.select { |name| @counts[name].gold.positive? }
      scored.empty? ? nil : (scored.sum { |name| f1.(name, scope: scope, range: range) } / scored.size).round(4)
    end

    { "out_of_scope_labels" => @out_of_scope.sort.to_h, "in_range_values" => @in_range.sort.to_h,
      "macro_f1_in_scope" => macro.(scope: false, range: false),
      "macro_f1_all_labels" => macro.(scope: true, range: false),
      "macro_f1_range_aware" => macro.(scope: false, range: true),
      "macro_f1_all_labels_range_aware" => macro.(scope: true, range: true) }
  end

  def report
    labelled = @counts.select { |_, counts| counts.gold.positive? }

    { "cards" => @cards, "asked_model" => @asked_model, "evaluated_at" => Time.current.iso8601,
      "acceptance_mode" => Extraction::Acceptance.mode,
      "acceptance_policy" => Extraction::Acceptance.policy_version,
      "partial_gold" => @partial,
      "macro_f1" => labelled.empty? ? nil : (labelled.values.sum(&:f1) / labelled.size).round(4),
      "attributes" => @counts.to_h { |name, counts| [ name, counts.to_h.stringify_keys ] },
      "variants" => variants,
      "calibration" => BUCKETS.to_h { |floor| [ floor.to_s, { "values" => @buckets[floor][0], "correct" => @buckets[floor][1] } ] } }
  end

  # One line for a whole run: quality, how literally the values match gold, and what a person is left with.
  def totals
    labelled = @counts.values.select { |counts| counts.gold.positive? }
    sum = ->(field) { labelled.sum(&field) }

    { cards: @cards, asked_model: @asked_model, macro_f1: labelled.empty? ? nil : (labelled.sum(&:f1) / labelled.size).round(3),
      traffic_f1: traffic_f1,
      exact: labelled.empty? || sum.(:correct).zero? ? nil : (sum.(:exact).to_f / sum.(:correct)).round(3),
      accepted_precision: sum.(:accepted).zero? ? nil : (sum.(:accepted_correct).to_f / sum.(:accepted)).round(3),
      coverage: ratio(@counts.values.sum(&:predicted), @counts.values.sum(&:cards)),
      review: ratio(@counts.values.sum(&:review), @counts.values.sum(&:cards)),
      weakest: labelled.empty? ? nil : @counts.select { |_, counts| counts.gold.positive? }.min_by { |_, counts| counts.f1 }.then { |name, counts| "#{name} #{counts.f1.round(2)}" } }
  end

  # Categories with the most scored values, worst first: F1, coverage and review share of each.
  def segments(limit = 10)
    @segments.select { |_, counts| counts.gold.positive? }.max_by(limit * 3) { |_, counts| counts.gold }
             .min_by(limit) { |_, counts| counts.f1 }
             .map { |title, counts| { title: title, values: counts.gold, f1: counts.f1, coverage: counts.coverage, review: counts.review_share } }
  end

  def save! = PATH.write(JSON.pretty_generate(report))

  # Conservative 95% Wilson lower bound; zero observations do not establish safety.
  def self.precision_lower_bound(correct, total)
    return 0.0 if total.zero?

    p = correct.to_f / total
    z = 1.96
    ((p + z**2 / (2 * total) - z * Math.sqrt(p * (1 - p) / total + z**2 / (4 * total**2))) /
      (1 + z**2 / total)).round(4)
  end

  def to_markdown = self.class.markdown(report, @catalog)

  def self.markdown(report, catalog = Extraction::Catalog.current)
    lines = [ "Cards: #{report['cards']}, of them sent to the model: #{report['asked_model']}. " \
              "Macro-F1: #{report['macro_f1'] || '—'}", "",
              "| Attribute | Precision | Recall | F1 | Coverage | Accepted precision | To review |", "|---|---|---|---|---|---|---|" ]

    report["attributes"].each do |name, counts|
      title = catalog.attributes[name]&.label || name
      scored = counts["gold"].positive?
      lines << "| #{title} | #{scored ? counts['precision'] : '—'} | #{scored ? counts['recall'] : '—'} | " \
               "#{scored ? counts['f1'] : '—'} | #{counts['coverage']} | #{scored ? counts['accepted_precision'] : '—'} | " \
               "#{counts['review_share']} |"
    end

    lines.join("\n")
  end

  private

  def traffic_f1
    weights = self.class.traffic
    weighted = @counts.select { |name, counts| counts.gold.positive? && weights[name] }
    total = weighted.sum { |name, _| weights[name] }
    (weighted.sum { |name, counts| weights[name] * counts.f1 } / total).round(3) if total.positive?
  end

  def ratio(part, whole) = whole.zero? ? 0.0 : (part.to_f / whole).round(3)

  # The gold is normalized for the card's category, as the prediction was: a smartwatch size in mm must not be read
  # with a TV's range. A model name without a digit is not the gold's model when the gold has a model number
  # ("Galaxy" is not "Galaxy Tab A11"); the substring match of Model#same? stays for the pipeline itself.
  def same?(finding, gold, category = nil)
    attribute = @catalog.attributes.fetch(finding.attribute)
    expected = attribute.kind.normalize(gold, category: category) || gold
    return false if attribute.kind.is_a?(Extraction::Kinds::Model) && expected.to_s.match?(/\d/) && !finding.value.to_s.match?(/\d/)

    attribute.kind.same?(finding.value, expected)
  end

  # A gold range of a numeric attribute and whether the predicted number is inside it.
  module GoldRange
    NUMBER = /\d+(?:[.,]\d+)?/
    NUMERIC = [ Extraction::Kinds::Diagonal, Extraction::Kinds::Battery, Extraction::Kinds::Quantity ].freeze

    module_function

    def inside?(finding, gold, catalog)
      return false unless NUMERIC.any? { |kind| catalog.attributes.fetch(finding.attribute).kind.is_a?(kind) }

      found = bounds(gold.to_s.downcase)
      value = number(finding.value.to_s)
      return false unless found && value

      value.between?(*found)
    end

    def bounds(text)
      numbers = text.scan(NUMBER).map { |found| number(found) }
      if numbers.size >= 2 && text.match?(/\d\s*(?:\S{0,3})\s*(?:-|–|—|до)\s*\d/)
        numbers.first(2).minmax
      elsif numbers.size == 1 && text.match?(/(?:и\s+более|и\s+выше|\+|\Aот|\A(?:более|свыше))/)
        [ numbers.first, Float::INFINITY ]
      elsif numbers.size == 1 && text.match?(/\A(?:до|менее|меньше)/)
        [ -Float::INFINITY, numbers.first ]
      end
    end

    def number(text) = text[NUMBER]&.tr(",", ".")&.to_f
  end
end
