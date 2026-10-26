# The metrics page in the words of someone who fills catalogue cards: "79 out of 100", not "0.79" or F1.
module MetricsHelper
  # The confidence words of the interface, where each starts, and what happens to such a value.
  CONFIDENCE_WORDS = [
    [ "sure", "80 and above", 0.8, "accepted when they pass the field's threshold and the source rules" ],
    [ "unsure", "50 to 79", 0.5, "these go to review" ],
    [ "not sure", "below 50", nil, "these go to review" ]
  ].freeze

  # Fewer values than this say nothing about a word.
  FEW = 20

  # Where a bar turns green, yellow or red, on the "out of 100" scale the numbers next to it are written in.
  # The legend under the quality table says the same.
  GOOD = 90
  FAIR = 75

  # The pilot's dataset, measured once and copied here: README.md, the sections on the Acme Retail catalog (catalog_dump) and
  # the whole Acme Retail catalog (bin/compare, rules + tagger + reference + the category's usual value, LLM off).
  # The app does not rerun it; update both together.
  BENCHMARK = [
    { score: 0.828, title: "10 pilot categories", detail: "7,215 test cards" },
    { score: 0.687, title: "New products only", detail: "1,455 cards not seen in training" },
    { score: 0.717, title: "Whole catalog", detail: "239 categories, 20 thousand test cards" }
  ].freeze
  # README: precision of values accepted without a person, 0.93–0.96 (10 categories).
  BENCHMARK_ACCEPTED = (0.93..0.96)

  def out_of_100(share) = (share.to_f * 100).round

  # "0.83": a decimal for the specialists who compare with the README.
  def decimal(number, digits = 2) = format("%.#{digits}f", number.to_f)

  # The colour of a bar by the number written next to it (0–100), so "90" is never yellow because it was 89.7.
  def quality_tone(score)
    score >= GOOD ? "bg-emerald-500" : score >= FAIR ? "bg-amber-500" : "bg-brand-500"
  end

  # The groups of ApplicationHelper::OUTCOMES, in its order, by the name the headline uses for each.
  OUTCOME_KEYS = %i[accepted waiting checked missing].freeze

  # What became of the values: { accepted: { label:, colour:, count:, share:, rest: }, ... }. The shares are whole
  # percents that add up to 100 (largest remainder), so the numbers of the headline sum up; rest is the other values.
  def outcomes(by_status)
    counts = ApplicationHelper::OUTCOMES.map { |_, statuses, _| by_status.values_at(*statuses).compact.sum }
    total = counts.sum
    exact = counts.map { |count| total.zero? ? 0.0 : count * 100.0 / total }
    shares = exact.map(&:floor)
    exact.each_index.sort_by { |index| [ shares[index] - exact[index], index ] }.first(total.zero? ? 0 : 100 - shares.sum).each { |index| shares[index] += 1 }

    OUTCOME_KEYS.each_with_index.to_h do |key, index|
      label, _, colour = ApplicationHelper::OUTCOMES[index]
      [ key, { label: label, colour: colour, count: counts[index], share: shares[index], rest: total - counts[index] } ]
    end
  end

  # "6%"; "under 1%" when there are such values but they round to nothing, and "over 99%" when they round to all,
  # so "100%" is never followed by "Left to people: under 1%".
  def share_phrase(outcome)
    if outcome[:share].zero? && outcome[:count].positive? then "under 1%"
    elsif outcome[:share] == 100 && outcome[:rest].positive? then "over 99%"
    else "#{outcome[:share]}%"
    end
  end

  # The part of the headline after what the system filled itself: what is left to people, what they have done,
  # what was not found. With the first share it makes 100%.
  def remainder_sentence(outcomes)
    waiting, checked, missing = outcomes.values_at(:waiting, :checked, :missing)
    people = waiting[:count].positive? ? "Left to people: #{share_phrase(waiting)}, the disputed values" : "No disputed values are left"
    if checked[:count].positive?
      people += waiting[:count].positive? ? "; they have already checked #{share_phrase(checked)}" : ": people checked #{share_phrase(checked)}"
    end
    [ "#{people}.", ("Another #{share_phrase(missing)} was not found in the card text." if missing[:count].positive?) ].compact.join(" ")
  end

  # [name, title, counts] of every attribute, weakest first; the ones without labels last.
  def quality_rows(report)
    report["attributes"].map { |name, counts| [ name, Extraction::Catalog.current.attributes[name]&.label || name, counts ] }
                        .sort_by { |_, title, counts| [ counts["gold"].to_i.positive? ? counts["f1"].to_f : 2, title ] }
  end

  def labelled(rows) = rows.select { |_, _, counts| counts["gold"].to_i.positive? }

  # The weaker side of an attribute, said the way the table says it.
  def weak_side(title, counts)
    if counts["precision"].to_f <= counts["recall"].to_f
      "\"#{title}\": #{out_of_100(counts["precision"])} out of 100 right"
    else
      "\"#{title}\": #{out_of_100(counts["recall"])} out of 100 found"
    end
  end

  # "Weakest: "Connection type": 79 out of 100 right, "Processor": 83 out of 100 found. The rest: at least 90 out of 100."
  # The claim about review is only made when it holds for both.
  def weakest_summary(rows)
    scored = labelled(rows)
    return if scored.size < 3

    weakest, rest = scored.first(2), scored.drop(2)
    floor = rest.map { |_, _, counts| [ counts["precision"].to_f, counts["recall"].to_f ].min }.min
    share = scored.sum { |_, _, counts| counts["review"].to_i }.to_f / [ scored.sum { |_, _, counts| counts["cards"].to_i }, 1 ].max
    more_review = weakest.all? { |_, _, counts| counts["review_share"].to_f > share }

    [ "Weakest: #{weakest.map { |_, title, counts| weak_side(title, counts) }.join(", ")}.",
      "The rest: at least #{(floor * 100).round} out of 100.",
      ("Such values go to review more often." if more_review) ].compact.join(" ")
  end

  # The confidence words with how right they were on labelled cards: [word, range, floor, fate, right, all].
  def calibration_rows
    CONFIDENCE_WORDS.map do |word, range, floor, fate|
      right, all = confidence_track_record&.dig(word) || [ 0, 0 ]
      [ word, range, floor, fate, right, all ]
    end
  end

  # "right 95 out of 100", or "too little data" when there are too few such values to tell.
  def track_record_share(right, all) = all >= FEW ? "right #{(right * 100.0 / all).floor} out of 100" : "too little data"
end
