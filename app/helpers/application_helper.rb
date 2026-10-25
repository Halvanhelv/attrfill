module ApplicationHelper
  # label, badge classes, dot colour
  STATUS = {
    "accepted" => [ "Accepted", "bg-emerald-50 text-emerald-700", "bg-emerald-500" ],
    "approved" => [ "Approved", "bg-sky-50 text-sky-700", "bg-sky-500" ],
    "corrected" => [ "Corrected", "bg-sky-50 text-sky-700", "bg-sky-500" ],
    "review" => [ "Needs review", "bg-amber-50 text-amber-700", "bg-amber-500" ],
    "missing" => [ "Not found", "bg-surface text-muted", "bg-zinc-400" ],
    "rejected" => [ "No value", "bg-surface text-muted", "bg-zinc-400" ] # the reviewer's own words: the button says the same
  }.freeze

  # Where a value came from, in the words of someone who fills catalogue cards, not of the pipeline.
  SOURCE = { "seller" => "seller data", "title" => "title", "description" => "description", "tagger" => "trained extraction model",
             "reference" => "other variants of the product", "prior" => "other products", "llm" => "language model (LLM)" }.freeze

  # label, badge classes, dot colour
  BATCH_STATUS = {
    "pending" => [ "Queued", "bg-surface text-muted", "bg-zinc-400" ],
    "processing" => [ "Processing", "bg-sky-50 text-sky-700", "bg-sky-500 animate-pulse" ],
    "done" => [ "Done", "bg-emerald-50 text-emerald-700", "bg-emerald-500" ],
    "failed" => [ "Failed", "bg-brand-50 text-brand-700", "bg-brand-600" ]
  }.freeze

  # Groups of value statuses the summaries count, in the order they are shown.
  OUTCOMES = [
    [ "Accepted automatically", %w[accepted], "bg-emerald-500" ],
    [ "Needs review", %w[review], "bg-amber-500" ],
    [ "Checked by a person", %w[approved corrected], "bg-sky-500" ],
    [ "Not found", %w[missing rejected], "bg-zinc-400" ]
  ].freeze

  # Lucide icons (lucide.dev, ISC licence), inlined so the page needs no icon font.
  ICONS = {
    "sparkles" => '<path d="M9.94 14.06 4 20"/><path d="m12 3 1.9 5.8L20 10l-6.1 1.2L12 17l-1.9-5.8L4 10l6.1-1.2Z"/>',
    "file" => '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/>',
    "upload" => '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m17 8-5-5-5 5"/><path d="M12 3v12"/>',
    "download" => '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/>',
    "check" => '<path d="M20 6 9 17l-5-5"/>',
    "check-circle" => '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
    "x" => '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    "pencil" => '<path d="M21.17 6.81a1 1 0 0 0-3.98-3.98L3.84 16.17a2 2 0 0 0-.5.83l-1.32 4.35a.5.5 0 0 0 .62.62l4.35-1.32a2 2 0 0 0 .83-.5Z"/>',
    "chart" => '<path d="M3 3v16a2 2 0 0 0 2 2h16"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>',
    "inbox" => '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11Z"/>',
    "arrow-left" => '<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>',
    "arrow-right" => '<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>',
    "chevron-down" => '<path d="m6 9 6 6 6-6"/>',
    "chevron-right" => '<path d="m9 18 6-6-6-6"/>',
    "alert" => '<circle cx="12" cy="12" r="10"/><path d="M12 8v4"/><path d="M12 16h.01"/>',
    "loader" => '<path d="M21 12a9 9 0 1 1-6.22-8.56"/>',
    "cpu" => '<rect width="16" height="16" x="4" y="4" rx="2"/><rect width="6" height="6" x="9" y="9" rx="1"/><path d="M15 2v2"/><path d="M15 20v2"/><path d="M2 15h2"/><path d="M2 9h2"/><path d="M20 15h2"/><path d="M20 9h2"/><path d="M9 2v2"/><path d="M9 20v2"/>',
    "keyboard" => '<path d="M10 8h.01"/><path d="M12 12h.01"/><path d="M14 8h.01"/><path d="M16 12h.01"/><path d="M18 8h.01"/><path d="M6 8h.01"/><path d="M7 16h10"/><path d="M8 12h.01"/><rect width="20" height="16" x="2" y="4" rx="2"/>',
    "plus" => '<path d="M5 12h14"/><path d="M12 5v14"/>',
    "eye" => '<path d="M2.06 12.35a1 1 0 0 1 0-.7 10.75 10.75 0 0 1 19.88 0 1 1 0 0 1 0 .7 10.75 10.75 0 0 1-19.88 0"/><circle cx="12" cy="12" r="3"/>',
    "arrow-down" => '<path d="M12 5v14"/><path d="m19 12-7 7-7-7"/>',
    "tag" => '<path d="M12.59 2.59A2 2 0 0 0 11.17 2H4a2 2 0 0 0-2 2v7.17a2 2 0 0 0 .59 1.42l8.7 8.7a2.43 2.43 0 0 0 3.42 0l6.58-6.58a2.43 2.43 0 0 0 0-3.42Z"/><circle cx="7.5" cy="7.5" r="1.25" fill="currentColor"/>',
    "sun" => '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>',
    "moon" => '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
    "monitor" => '<rect width="20" height="14" x="2" y="3" rx="2"/><path d="M8 21h8"/><path d="M12 17v4"/>',
    "copy" => '<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
    "printer" => '<path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><path d="M6 9V3a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v6"/><rect x="6" y="14" width="12" height="8" rx="1"/>',
    "undo" => '<path d="M3 7v6h6"/><path d="M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/>',
    "link" => '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
    "clock" => '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    "info" => '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
    "user-check" => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="m16 11 2 2 4-4"/>',
    "list-checks" => '<path d="m3 17 2 2 4-4"/><path d="m3 7 2 2 4-4"/><path d="M13 6h8"/><path d="M13 12h8"/><path d="M13 18h8"/>'
  }.freeze

  def icon(name, size: 20, **options)
    tag.svg ICONS.fetch(name).html_safe, xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", width: size, height: size,
            fill: "none", stroke: "currentColor", "stroke-width": 2, "stroke-linecap": "round", "stroke-linejoin": "round",
            "aria-hidden": true, class: [ "shrink-0", options[:class] ]
  end

  def status_badge(status)
    label, classes, dot = STATUS.fetch(status, [ status, "bg-surface text-muted", "bg-zinc-300" ])
    tag.span(class: "badge #{classes}") { tag.span("", class: "dot #{dot}") + tag.span(label) }
  end

  def batch_status_badge(status)
    label, classes, dot = BATCH_STATUS.fetch(status, [ status, "bg-surface text-muted", "bg-zinc-300" ])
    tag.span(class: "badge #{classes}") { tag.span("", class: "dot #{dot}") + tag.span(label) }
  end

  def source_label(source) = SOURCE.fetch(source.to_s, "—")

  def percent(share) = "#{(share.to_f * 100).round}%"

  # 12,345: thousands separated by commas.
  def num(number) = number_with_delimiter(number.to_i, delimiter: ",")

  # "Oct 18, 21:55" in Moscow time; the year only when it is not this one ("Oct 18, 2025, 21:55").
  def human_time(time)
    time = time.in_time_zone("Moscow")
    year = time.year == Time.current.year ? "" : ", #{time.year}"
    "#{time.strftime('%b')} #{time.day}#{year}, #{time.strftime('%H:%M')}"
  end

  # Did the seller fill this attribute in the card? Matched by the seller keys of the catalog, as the pipeline does;
  # the value's own source can say "title" even then, when the title said the same.
  def seller_gave?(card, value)
    keys = Extraction::Catalog.current.attributes[value.name]&.seller_keys or return false
    card.seller_attributes.any? { |key, given| given.present? && keys.include?(Extraction::Text.key(key)) }
  end

  # What to do about a file that could not be read, in plain words; the raw error is shown under it for a developer.
  def batch_error_hint(error)
    case error.to_s
    when /JSON|ParserError/ then "The file does not look like JSON: it may be truncated or in another format. Check that it starts with [ or {, or save it as CSV."
    when /CSV|Malformed|Unclosed quoted/ then "CSV error: usually an unclosed quote or a different column separator. Save the file from your spreadsheet as \"CSV UTF-8\"."
    when /title|заголов|heading/i then "The file has no product title column. Name it \"title\"."
    when /encoding|UTF-8|invalid byte/i then "The file is in another encoding. Save it as UTF-8."
    else "Check the format: CSV, TSV, JSON or JSONL with a product title column."
    end
  end

  # English plural: plural(3, "card", "cards") → "cards".
  def plural(count, one, other) = count == 1 ? one : other

  def confidence_tone(confidence)
    confidence >= 0.8 ? "bg-emerald-500" : confidence >= 0.5 ? "bg-amber-500" : "bg-brand-500"
  end

  def confidence_word(confidence) = confidence >= 0.8 ? "sure" : confidence >= 0.5 ? "unsure" : "not sure"

  # Confidence on the scale people read: out of 100, as "97" rather than "0.97". It is calibrated on labelled cards,
  # so "97" means such values were right about 97 times out of 100.
  def confidence_score(confidence) = (confidence.to_f * 100).round

  # "95 times out of 100".
  def times_out_of_100(count) = "#{count} #{plural(count, "time", "times")} out of 100"

  # The bar is decoration; the number (and with words: the word) carries the meaning, so it is not colour alone.
  # The tooltip says what the word has meant on labelled cards, when the evaluation knows.
  def confidence_bar(confidence, words: false)
    score = confidence_score(confidence)
    word = confidence_word(confidence)
    record = track_record_phrase(word)
    hint = [ ("#{word.capitalize}: on labelled cards such values were #{record}" if record),
             "Automatic acceptance depends on the field's threshold and the source; the outcome is shown in the status" ].compact.join(". ")
    tag.div class: "flex items-center gap-2.5", title: hint do
      tag.div(class: "meter relative h-1.5 w-16 shrink-0 overflow-hidden rounded-full bg-surface sm:w-20", "aria-hidden": true) do
        tag.div("", class: "h-full rounded-full #{confidence_tone(confidence)}", style: "width: #{score}%")
      end + tag.span(class: "text-sm whitespace-nowrap tabular-nums text-muted") do
        words ? safe_join([ tag.span(confidence_word(confidence).capitalize, class: "font-medium text-ink"), " · #{score}" ]) : score.to_s
      end
    end
  end

  # How right each confidence word turned out on labelled cards: { "sure" => [right, all], ... }, nil without an evaluation.
  # Read from the last evaluation report (bin/extract); the buckets are cut where confidence_word changes its word.
  def confidence_track_record
    return @confidence_track_record if defined?(@confidence_track_record)

    report = Evaluation.last
    @confidence_track_record = report && report["calibration"].each_with_object(Hash.new { |hash, key| hash[key] = [ 0, 0 ] }) do |(floor, bucket), words|
      counts = words[confidence_word(floor.to_f)]
      counts[0] += bucket["correct"].to_i
      counts[1] += bucket["values"].to_i
    end
  end

  # "right 95 times out of 100" for a confidence word, or nil when the evaluation has too few such values to say.
  def track_record_phrase(word)
    right, all = confidence_track_record&.dig(word)
    return if all.to_i < 20

    "right #{times_out_of_100((right * 100.0 / all).floor)}"
  end

  # The acceptance rule in force, in words. The confidence word is not the rule: in the strict pilot policy
  # "sure" (80+) values still go to a person below 98 and for the fields and categories of config/acceptance.yml.
  def acceptance_rule_sentence
    if Extraction::Acceptance.mode == "strict"
      policy = Extraction::Acceptance.policy
      fields = policy.dig("manual_review", "attributes").filter_map { |name| Extraction::Catalog.current.attributes[name]&.label }
      categories = policy.dig("manual_review", "categories").filter_map { |name| Extraction::Catalog.current.categories[name]&.label }
      always = [ (fields.map(&:downcase).to_sentence(two_words_connector: " and ", last_word_connector: " and ").upcase_first if fields.any?),
                 ("all fields of the categories #{categories.map { |title| "\"#{title}\"" }.to_sentence(two_words_connector: " and ", last_word_connector: " and ")}" if categories.any?) ].compact
      "Strict mode is on: a value is accepted without a person only with confidence of at least " \
        "#{confidence_score(policy.fetch("minimum_confidence"))} out of 100 and found in the text or the seller's data." +
        (always.any? ? " #{always.join(", as well as ")} are always checked by a person." : "") + " Everything else goes to review."
    else
      "Standard mode is on: a value is accepted without a person when it reaches its field's threshold (usually 80 out of 100); everything else goes to review."
    end
  end

  # Why a value is waiting for a person, in one sentence — not where it was found (value_reason says that).
  def doubt_reason(value)
    if Extraction::Acceptance.review_required?(value.name, category: value.card.detected_category)
      return "This field or category always requires a person to check it, even at high confidence"
    end
    record = track_record_phrase(confidence_word(value.confidence))
    if value.alternatives.any?
      "The card has another possible answer too: which one is right?"
    elsif %w[reference prior].include?(value.source)
      "The system did not recognize this in the card text and filled in a value: compare it with the text."
    elsif record
      "Values with this confidence were #{record}. The current acceptance rules require this field to be checked."
    else
      "The value did not pass the automatic acceptance rules: it needs to be confirmed."
    end
  end

  # Why the value is what it is, in one plain sentence: where it was found and how; who checked it, if a person did.
  # The quote is only given when it really is in the card text.
  def value_reason(value)
    return "Checked by a person · #{human_time(value.reviewed_at)}" if (value.approved? || value.corrected?) && value.reviewed_at
    return "A person marked that there is no value" if value.rejected?
    return "Neither in the card text nor in other variants of this product" if value.value.blank?

    raw = value.raw.to_s.strip.sub(%r{[/\\,;:.\s-]+\z}, "")
    quote = raw.present? ? "\"#{raw.truncate(40)}\"" : nil
    where = { "title" => "in the title", "description" => "in the description" }.fetch(value.source, "in the text")
    same = value.raw.to_s.casecmp?(value.value.to_s)

    if value.name == "color" && value.rule == "mention"
      return "The color #{quote} is mentioned, but it is unclear whether it is the product's own: check the context"
    end

    reason =
      case [ value.source, value.rule ]
      in [ "seller", "raw" ] then "Given by the seller, recorded as is"
      in [ "seller", _ ] then "Given by the seller in their specifications"
      in [ "reference", "identity_pending" ] then "Suggested by a similar product: confirm the brand and model first"
      in [ "reference", "unanimous" ] then "All other variants of this product say so (the system did not recognize it in the text)"
      in [ "reference", "majority" ] then "Most other variants of this product say so (the system did not recognize it in the text)"
      in [ "reference", _ ] then "Another variant of this product says so (the system did not recognize it in the text)"
      in [ "prior", "context" ] then "A guess from other products. The card text does not confirm the value: check it"
      in [ "prior", _ ] then "Typical for products in the \"#{value.card.category_title}\" category (the system did not recognize it in the text)"
      in [ "llm", _ ] then "Suggested by a neural network: compare with the text"
      in [ "tagger", _ ] then "Recognized from similar records: #{quote}"
      in [ _, "dictionary" ] then same ? "In the dictionary: #{quote} #{where}" : "In the dictionary: #{quote} #{where}, meaning \"#{value.value}\""
      in [ _, "after_brand" | "after_brand_plain" | "after_guess" | "product_line" ] then "#{where.capitalize} right after the brand: #{quote}"
      in [ _, "combo" | "combo_unitless" ] then "An entry like #{quote} #{where}: memory written with a slash"
      in [ _, "component_sum" ] then "Sum of the fridge and freezer compartment volumes #{where}: #{quote}"
      in [ _, "family" ] then "#{where.capitalize}, the processor family is given: #{quote}"
      in [ _, "unit" | "pixels" ] then "A number with a unit #{where}: #{quote}"
      in [ _, "bare" ] then value.confidence >= 0.8 ? "The number #{quote} #{where}" : "A bare number #{quote} #{where}: unclear what it refers to"
      in [ _, "code" ] then "Looks like a model code #{where}: #{quote}"
      in [ _, "context" | "mention" ] then "#{where.capitalize}, next to a cue word: #{quote}"
      in [ _, _ ] then [ "Found #{where}", quote ].compact.join(": ")
      end

    return reason if value.alternatives.none?

    other = value.alternatives.one? ? "There is another possible answer" : "There are other possible answers"
    "#{reason}. #{other}: #{value.alternatives.join(", ")}"
  end

  # A horizontal bar split by outcome; counts is { status => number }.
  def outcome_bar(counts, height: "h-2")
    total = counts.values.sum
    return tag.div("", class: "#{height} rounded-full bg-surface") if total.zero?

    summary = OUTCOMES.filter_map { |label, keys, _| count = counts.values_at(*keys).compact.sum; "#{label}: #{count}" if count.positive? }.join(", ")
    tag.div class: "flex #{height} gap-0.5 overflow-hidden rounded-full", role: "img", "aria-label": summary do
      safe_join(OUTCOMES.filter_map do |label, keys, color|
        count = counts.values_at(*keys).compact.sum
        tag.div("", class: color, style: "width: #{count * 100.0 / total}%", title: "#{label}: #{count}") if count.positive?
      end)
    end
  end

  # The card text with the fragments values were read from marked; each <mark> names its values for the trace controller.
  # Overlapping fragments merge into one that stands for all their values ("iPhone 15" → brand and model).
  def highlight_sources(text, values)
    return "" if text.blank?

    down = text.downcase
    spans = values.filter_map do |value|
      next if value.raw.blank? || value.value.blank? || %w[seller reference prior].include?(value.source)

      start = down.index(value.raw.downcase) or next
      [ start, start + value.raw.length, [ value ] ]
    end
    spans = spans.sort_by { |start, finish, _| [ start, -finish ] }.each_with_object([]) do |(start, finish, found), merged|
      if merged.any? && start < merged.last[1]
        merged.last[1] = [ merged.last[1], finish ].max
        merged.last[2] += found
      else
        merged << [ start, finish, found ]
      end
    end

    position = 0
    parts = spans.flat_map do |start, finish, found|
      titles = found.map(&:title).join(", ")
      mark = tag.mark(text[start...finish], class: "source-mark", title: titles,
                      data: { trace_target: "mark", trace_keys: found.map { |value| dom_id(value) }.join(" "),
                              action: "mouseenter->trace#show mouseleave->trace#hide" })
      [ text[position...start], mark, tag.span(" (#{titles})", class: "sr-only") ].tap { position = finish }
    end
    safe_join(parts + [ text[position..] ])
  end

  # A section of the header menu. On a phone only icons fit (the label stays for screen readers); a card page counts as "Card".
  # The waiting badge carries data-waiting-count so that scripts can keep it current after a decision.
  def nav_link(title, path, icon_name, count: nil)
    active = current_page?(path) || (path != root_path && request.path.start_with?(path)) ||
             (path == root_path && request.path.start_with?("/cards"))
    link_to path, class: "pill relative shrink-0 max-sm:h-12 max-sm:w-14 max-sm:flex-col max-sm:justify-center max-sm:gap-0.5 max-sm:px-0 max-sm:py-1",
                  title: title, "aria-current": ("page" if active) do
      badge = if count
        tag.span(count, class: "rounded-full bg-brand-600 px-1.5 text-xs text-white tabular-nums max-sm:absolute max-sm:-top-1 max-sm:-right-1 max-sm:text-2xs #{"hidden" unless count.positive?}",
                        "aria-hidden": true, data: { waiting_count: true }) +
          tag.span(count.positive? ? ", #{count} waiting" : "", class: "sr-only", data: { waiting_label: true })
      end
      icon(icon_name, size: 18) + tag.span(title, class: "max-sm:text-2xs max-sm:leading-none") + (badge || "".html_safe)
    end
  end
end
