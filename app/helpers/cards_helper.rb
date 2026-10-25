# The card page: what goes to the site, how to take it away, and where "back" leads.
module CardsHelper
  # Statuses whose value a shopper would see: the system's own and a person's.
  PUBLISHED = %w[accepted approved corrected].freeze

  def published?(value) = PUBLISHED.include?(value.status) && value.value.present?

  # A person has decided on it, so the system's confidence no longer says anything.
  def reviewed?(value) = value.approved? || value.corrected? || value.rejected?

  # "Brand: Apple; Model: iPhone 15" — the format of the seller's field on the start page, so it pastes back as is.
  def card_export_text(values) = values.select { |value| published?(value) }.map { |value| "#{value.title}: #{value.value}" }.join("; ")

  # One card the way the file download writes it (Dataset::Writer): every attribute with its value, confidence (0–1, as
  # in the file), status and source, in the file's words (a person's decision is "accepted", a thrown-out value "missing").
  # On top of the file: whether a person checked it, and the display names of the keys.
  def card_export_json(card, values)
    attributes = values.to_h do |value|
      finding = value.to_finding
      [ value.name, { value: finding.value, confidence: finding.confidence.to_f.round(2), status: finding.status,
                      source: finding.source, checked_by_person: reviewed?(value) } ]
    end
    { id: card.external_id.presence || card.id.to_s, title: card.title, category: card.detected_category,
      attributes: attributes, titles: values.to_h { |value| [ value.name, value.title ] } }.to_json
  end

  # The dots under the outcome bar say what its colours are, in the words of its own tooltips and with the same counts.
  # "Auto-accepted" rather than "Accepted": the filter's "Accepted" also counts what a person checked.
  def card_outcome_legend(counts)
    items = ApplicationHelper::OUTCOMES.filter_map do |label, statuses, dot|
      count = counts.values_at(*statuses).compact.sum
      next unless count.positive?

      tag.li(class: "inline-flex items-center gap-1.5") do
        tag.span("", class: "dot #{dot}") + "#{label} " + tag.span(count, class: "font-semibold text-ink tabular-nums")
      end
    end
    tag.ul(safe_join(items), class: "flex flex-wrap gap-x-4 gap-y-1")
  end

  # The reason line, with the fragment the value was read from marked the way the card text marks it: on a phone
  # the text is far above the row, so the row itself shows what lit up there. Only for values read from the text.
  def value_reason_marked(value)
    return reviewed_reason(value) if (value.approved? || value.corrected?) && value.reviewed_at

    reason = value_reason(value)
    return reason if value.raw.blank? || value.value.blank? || reviewed?(value) || %w[seller reference prior].include?(value.source)

    before, quote, after = reason.partition(/"[^"]+"|«[^»]+»/)
    return reason if quote.empty? || !value.raw.strip.downcase.start_with?(quote[1..-2].delete_suffix("...").downcase)

    safe_join([ before, tag.span(quote, class: "reason-quote"), after ])
  end

  # The status as the table shows it: a "correction" to the very value the system had found is a confirmation.
  # Display only: the value stays "corrected", and the file writes both as "accepted".
  def shown_status(value)
    return value.status unless value.corrected? && value.value.present?

    value.value.strip.casecmp?(value.extracted_value.to_s.strip) ? "approved" : value.status
  end

  # Who settled the value, in the words of its status, and what the system had for a real correction.
  def reviewed_reason(value)
    time = human_time(value.reviewed_at)
    return "Confirmed by a person · #{time}" if shown_status(value) == "approved"

    found = value.extracted_value.presence
    found ? "Corrected by a person · #{time} · the system found \"#{found.truncate(40)}\"" : "Added by a person · #{time}"
  end

  # The keys of the review queue that work in the table too (inline_review_controller), for the values it shows:
  # "4/5 — other answer" only where a value has two other answers.
  def review_keys_hint(values, neighbour:)
    variants = values.select(&:review?).map { |value| review_variants(value).size }.max.to_i
    keys = [ [ [ "1" ], "correct" ], [ [ "2" ], "correct it" ], [ [ "3" ], "no value" ] ]
    keys << [ variants > 1 ? %w[4 5] : %w[4], "other answer" ] if variants.positive?
    keys += [ [ %w[↑ ↓], neighbour ], [ [ "Z" ], "undo" ] ]
    items = keys.map do |caps, meaning|
      arrows = caps.first == "↑"
      joined = safe_join(caps.each_with_index.map { |cap, index| tag.kbd(cap, class: [ "kbd", ("ml-0.5" if arrows && index.positive?) ]) }, arrows ? "" : "/")
      safe_join([ joined, " — #{meaning}" ])
    end
    safe_join([ "Keyboard: ", safe_join(items, " · ") ])
  end

  # Back to where the person came from: the queue, the file the card belongs to, or a new card.
  def card_back_link(card)
    if params[:from] == "reviews" then [ "To review", reviews_path ]
    elsif card.batch then [ "File \"#{card.batch.name.truncate(40)}\"", batch_path(card.batch) ]
    else [ "New card", new_card_path ]
    end
  end

  # The confidence column: a person's decision is shown as one, not as the system's "Confident · 100".
  def value_assessment(value)
    if reviewed?(value)
      tag.span(class: "inline-flex items-center gap-1.5 text-sm font-medium text-sky-700") { icon("user-check", size: 16) + "Checked by a person" }
    elsif value.value.present?
      confidence_bar(value.confidence, words: true)
    else
      tag.span("—", class: "text-muted", "aria-hidden": true) + tag.span("none", class: "sr-only")
    end
  end
end
