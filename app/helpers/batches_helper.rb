# The file pages: the list of uploads and the result of one file.
module BatchesHelper
  # Statuses a file that is still being worked on has; the pages poll while they last.
  RUNNING = %w[pending processing].freeze

  # Extensions the upload field offers, and the types for pickers that match by type (Android, iOS "Files").
  ACCEPT = ".csv,.tsv,.txt,.json,.jsonl,.ndjson,text/csv,text/tab-separated-values,application/json,application/x-ndjson,text/plain".freeze

  # One line of "Before → after": the share of cards (0–100) where the seller gave the attribute and where it is filled now.
  FillRow = Data.define(:title, :count, :before, :after) do
    def gain = after.round - before.round
  end

  # Columns of the downloaded file (Dataset::Writer::HEADERS) in the words of the person who opens it.
  EXPORT_COLUMNS = { "id" => "card id", "category" => "category", "attribute" => "attribute", "value" => "value",
                     "confidence" => "confidence, 0–1", "status" => "status", "source" => "where it came from" }.freeze

  # Statuses of the downloaded file. A reviewer's decision is written as one of these (AttributeValue#to_finding).
  EXPORT_STATUSES = { "accepted" => "accepted: ready to publish, including values a person approved or corrected",
                      "review" => "waiting for review: the system is not sure, a person decides",
                      "missing" => "no value: not found, or a person marked that there is none" }.freeze

  def batch_running?(batch) = RUNNING.include?(batch.status)

  # Per attribute over the given cards, biggest gain first. A value counts as filled once it is accepted or a person
  # settled it; one waiting for review does not count yet. The headline and the list share this one computation.
  def fill_rows(cards)
    @fill_rows ||= {}
    @fill_rows[cards.object_id] ||= cards.flat_map { |card| card.attribute_values.map { |value| [ card, value ] } }
      .group_by { |_, value| value.title }
      .map do |title, pairs|
        seller = pairs.count { |card, value| seller_gave?(card, value) }
        filled = pairs.count { |_, value| value.value.present? && %w[accepted approved corrected].include?(value.status) }
        FillRow.new(title: title, count: pairs.size, before: seller * 100.0 / pairs.size, after: filled * 100.0 / pairs.size)
      end
      .sort_by { |row| -(row.after - row.before) }
  end

  # All attributes together, weighted by how many cards have each: the share of all fields.
  def fill_total(rows)
    count = rows.sum(&:count)
    return if count.zero?

    FillRow.new(title: "All attributes", count: count,
                before: rows.sum { |row| row.before * row.count } / count, after: rows.sum { |row| row.after * row.count } / count)
  end

  # "+77", "±0", "−3": the gain in percentage points, with a real minus sign.
  def fill_gain(row)
    gain = row.gain
    gain.positive? ? "+#{gain}" : gain.zero? ? "±0" : "−#{gain.abs}"
  end

  # Five seconds a value, as the review queue counts.
  def review_minutes(count) = (count * 5 / 60.0).ceil

  def cards_phrase(count) = "#{num(count)} #{plural(count, "card", "cards")}"

  def values_phrase(count) = "#{num(count)} #{plural(count, "value", "values")}"

  # The values of a card on the file's page, split in two. Those to check, or decided by a person (to revisit), get the
  # table with buttons; the rest are a light list. Buttons for every value of every card made the page ~900 KB, and
  # it is fetched whole after each decision.
  def checkable_values(values) = values.partition { |value| value.review? || reviewed?(value) }

  # The words next to a card's little bar, so that its colours are not the only sign: "6 of 7 accepted".
  def card_tally(values)
    accepted = values.count { |value| published?(value) }
    "#{num(accepted)} of #{num(values.size)} accepted"
  end

  # The little outcome bar of a card row. Spans, not divs: it sits in a <summary>, which takes phrasing content only.
  # Decoration for screen readers too: the tally and the badge beside it say the same in words.
  def card_bar(values)
    total = values.size.nonzero? or return tag.span("", class: "block h-1.5 rounded-full bg-surface", "aria-hidden": true)

    segments = ApplicationHelper::OUTCOMES.filter_map do |_, keys, color|
      count = values.count { |value| keys.include?(value.status) }
      tag.span("", class: "block #{color}", style: "width: #{count * 100.0 / total}%") if count.positive?
    end
    tag.span(safe_join(segments), class: "flex h-1.5 gap-0.5 overflow-hidden rounded-full", "aria-hidden": true)
  end

  # What the notification says when the file is ready, and the label of its button.
  def batch_done_message(batch, waiting)
    # No cards: nothing to check or download, so no button either; the page says what to fix.
    return [ "The file was processed, but no cards were found in it.", nil ] if batch.cards_count.zero?

    filled = "#{cards_phrase(batch.cards_count)} filled"
    return [ "Done: #{filled}, no disputed values.", "Download CSV" ] if waiting.zero?

    [ "Done: #{filled}, #{values_phrase(waiting)} #{plural(waiting, "waits", "wait")} for review.", "Review" ]
  end

  # The first rows of the downloaded file, built the way Dataset::Writer builds them.
  def export_rows(cards, limit: 5)
    rows = []
    cards.each do |card|
      result = card.to_result
      result.findings.each do |finding|
        rows << [ result.card.id, result.category.name, finding.attribute, finding.value, finding.confidence, finding.status, finding.source ]
        return rows if rows.size >= limit
      end
    end
    rows
  end
end
