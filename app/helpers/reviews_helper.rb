# The review queue (reviews/index, reviews/_value).
module ReviewsHelper
  # Which upload a card came from. Two cards with the same title from different files must not look like a duplicate.
  def review_origin(card)
    classes = "chip bg-panel text-xs text-muted"
    return tag.span(icon("sparkles", size: 14) + "Single card", class: classes) unless card.batch

    link_to batch_path(card.batch), class: "#{classes} transition hover:bg-control-hover hover:text-ink", title: "Open file" do
      icon("file", size: 14) + tag.span("File ", class: "sr-only") +
        tag.span("#{card.batch.name} · #{human_time(card.batch.created_at)}", class: "min-w-0 break-all")
    end
  end

  # The key that does what the button does. Shown on the row the keys act on (reviews.css); screen readers get
  # aria-keyshortcuts on the button instead, so the hint is hidden from them.
  # Values of the card whose words the text does not show: taken from other variants of the product or from the
  # category, or their fragment is not in the title or the description. The text panel says so instead of a mark.
  def review_not_in_text(card, values)
    text = [ card.title, card.description ].compact.join("\n").downcase
    values.select do |value|
      next false if value.source == "seller" # shown in the seller list under the text

      %w[reference prior].include?(value.source) || value.raw.blank? || !text.include?(value.raw.downcase)
    end
  end

  def review_key(key) = tag.kbd(key, class: "review-kbd kbd", "aria-hidden": true)

  # Other answers that get a button of their own next to "Correct", with the keys 4 and 5.
  def review_variants(value) = value.alternatives.first(2)

  # A variant on a button stays short; the whole text is in the aria-label and the title.
  def review_variant_label(variant) = variant.to_s.truncate(28)

  # The confidence words of the rows, with how often such values were right when the evaluation can tell.
  def review_confidence_legend
    [ [ 0.8, "80 and above", "high confidence; the acceptance rules decide whether it is accepted without a person" ],
      [ 0.5, "50 to 79", "so they are shown to you" ],
      [ 0.0, "below 50", "check them especially carefully" ] ].map do |confidence, range, otherwise|
      key = confidence_word(confidence)
      [ key.capitalize, range, track_record_phrase(key)&.then { |phrase| "#{phrase}, #{otherwise}" } || otherwise ]
    end
  end

  # What a screen reader hears before "Why we ask" and "Where from": how sure the system is.
  def review_described(value)
    "#{confidence_word(value.confidence).capitalize}, #{confidence_score(value.confidence)} out of 100."
  end

  # "Why we ask" of a row. With other possible answers it names them inside doubt_reason's own sentence
  # (they are the question), instead of a second sentence that says "other answer" again.
  def review_doubt(value)
    return doubt_reason(value) if value.alternatives.none?

    answers = value.alternatives.map { |alternative| "\"#{alternative}\"" }.join(", ")
    other = value.alternatives.one? ? "another possible answer" : "other possible answers"
    "The card also has #{other} — #{answers}. Which one is right?"
  end

  # "Where from" of a row: only where the shown value was found. What "Why we ask" already says is not repeated
  # a line lower: the other answers, and that the text did not have it (a value taken from other variants or from
  # the category). The parts are cut off as value_reason writes them; a wording it changes stays, never breaks.
  def review_source(value)
    reason = value_reason(value)
    if value.alternatives.any?
      other = value.alternatives.one? ? "There is another possible answer" : "There are other possible answers"
      return reason.delete_suffix(". #{other}: #{value.alternatives.join(", ")}")
    end
    return reason unless %w[reference prior].include?(value.source)

    reason.sub(" (the system did not recognize it in the text)", "")
  end

  # Duplicate input and evidence, not just the same title and value. Shared with
  # the server-side group preview so conflicting descriptions stay separate.
  def review_twin_key(value)
    ReviewGroup.key(value)
  end

  # "2 more of the same value in this set"; the queue controller keeps it on the first undecided one of them.
  def review_twins_note(others)
    "#{others} more of the same #{plural(others, "value", "values")} in this set"
  end

  # The rest of that line, in the number of the others: "another card", not "other cards".
  def review_twins_where(others)
    others == 1 ? "on another card with the same title; the decision can be repeated for it" :
                  "on other cards with the same title; the decision can be repeated for them"
  end
end
