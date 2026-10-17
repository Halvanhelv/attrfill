module Extraction
  # Card in, settled attributes out. The steps: find the category, read every source by rule, settle,
  # let the learned tagger read what is still missing or doubtful, take what known products of the same
  # brand and model said, take what most cards of the category say, and only then ask a model about the rest.
  class Pipeline
    Result = Data.define(:card, :category, :findings, :asked_model) do
      def [](attribute) = findings.find { |finding| finding.attribute == attribute.to_s }

      def values = findings.reject(&:missing?).to_h { |finding| [ finding.attribute, finding.value ] }
    end

    TEXT_SOURCES = %w[title description].freeze
    # Names are taken from the tagger as written; a value from a list or of a known shape must be recognised.
    TAGGED_AS_WRITTEN = [ Kinds::Brand, Kinds::Model, Kinds::Free ].freeze

    def initialize(catalog: Catalog.current, llm: LlmFallback.default, tagger: Tagger.current, reference: Reference.current,
                   prior: Prior.current, context: Context.current, resolver: Resolver, unreliable: Unreliable.current,
                   confirmed: Confirmed.current, learning: Learning.current)
      @catalog = catalog
      @llm = llm
      @tagger = tagger
      @reference = reference
      @prior = prior
      @context = context
      @resolver = resolver
      @unreliable = unreliable
      @confirmed = confirmed
      @learning = learning
    end

    def call(card)
      category = catalog.detect(card)
      candidates = candidates(card, category)
      findings = resolver.call(category.attributes, candidates, category: category.name)

      if tagger && (unsettled = unsettled(findings, category: category.name)).any?
        unsettled -= naming_attributes if category == catalog.generic && catalog.compatibility_only?(card)
        candidates += tagged(card, category, unsettled)
        findings = resolver.call(category.attributes, candidates, category: category.name)
      end

      # What people confirmed for a card of the same title.
      if confirmed && (unsettled = unsettled(findings, category: category.name)).any?
        candidates += confirmed.candidates(card, unsettled)
        findings = resolver.call(category.attributes, candidates, category: category.name)
      end

      if reference && (unsettled = unsettled(findings, category: category.name)).any?
        readings = reference.candidates(key(findings), category, unsettled)
        unless Reference::NAMING.all? { |name| findings.find { |finding| finding.attribute == name }&.accepted? }
          readings = readings.map { |reading| reading.with(origin: "unverified_identity", rule: "identity_pending") }
        end
        candidates += readings
        findings = resolver.call(category.attributes, candidates, category: category.name)
      end

      # Only for what nothing read at all: a guess must not raise a doubtful reading over the threshold.
      if (prior || context) && (empty = empty(findings)).any?
        readings = prior ? prior.candidates(category, empty) : []
        guesses = context ? context.candidates(card, category, empty, prior: readings) : []
        replaced = guesses.map(&:attribute)
        candidates += readings.reject { |reading| replaced.include?(reading.attribute) } + guesses
        findings = resolver.call(category.attributes, candidates, category: category.name)
      end

      # What the category's usual value settles costs no model call.
      unsettled = unsettled(findings, category: category.name).select { |attribute| attribute.worth_asking?(card.text) }
      asked = llm.present? && unsettled.any?

      if asked
        candidates += llm.candidates(card, category, unsettled)
        findings = resolver.call(category.attributes, candidates, category: category.name)
      end

      findings = learning.call(findings, candidates, catalog: catalog, category: category.name, card: card) if learning
      Result.new(card: card, category: category, findings: findings, asked_model: asked)
    end

    # The result of a card nothing could be read from: every attribute missing.
    def unread(card)
      Result.new(card: card, category: catalog.generic, findings: resolver.call(catalog.generic.attributes, [], category: catalog.generic.name),
                 asked_model: false)
    end

    # Every reading the rules make, before settling: what calibration counts.
    def candidates(card, category = catalog.detect(card))
      category.attributes.flat_map { |attribute| read(attribute, card, category) }
    end

    # What the tagger reads of the attributes the rules leave unsettled: what its confidence is measured on.
    def tagged_unsettled(card)
      category = catalog.detect(card)
      tagged(card, category, unsettled(resolver.call(category.attributes, candidates(card, category), category: category.name), category: category.name))
    end

    # The brand and model the rules read: what a card is looked up by among known products.
    def product_key(card)
      category = catalog.detect(card)
      key(resolver.call(category.attributes, candidates(card, category), category: category.name))
    end

    # What known products give for the attributes the rules leave unsettled: what their confidence is measured on.
    def referenced_unsettled(card)
      category = catalog.detect(card)
      findings = resolver.call(category.attributes, candidates(card, category), category: category.name)
      reference.candidates(key(findings), category, unsettled(findings, category: category.name))
    end

    # What the category's usual values give for the attributes the rules find nothing for: what their confidence is measured on.
    def prior_unsettled(card)
      category = catalog.detect(card)
      prior.candidates(category, empty(resolver.call(category.attributes, candidates(card, category), category: category.name)))
    end

    private

    attr_reader :catalog, :llm, :tagger, :reference, :prior, :context, :resolver, :unreliable, :confirmed, :learning

    def naming_attributes = Reference::NAMING.map { |name| catalog.attributes.fetch(name) }

    def key(findings)
      brand, model = Reference::NAMING.map { |name| findings.find { |finding| finding.attribute == name }&.value }
      Reference.key(brand, model)
    end

    def empty(findings) = findings.select(&:missing?).map { |finding| catalog.attributes.fetch(finding.attribute) }

    # A publication gate asks for human approval, not another machine guess.
    def unsettled(findings, category: nil)
      findings.reject do |finding|
        attribute = catalog.attributes.fetch(finding.attribute)
        finding.accepted? || (Acceptance.review_required?(finding.attribute, category: category) &&
          !finding.missing? && finding.confidence >= Acceptance.threshold(attribute))
      end.map { |finding| catalog.attributes.fetch(finding.attribute) }
    end

    def tagged(card, category, attributes)
      names = attributes.map(&:name)
      TEXT_SOURCES.flat_map do |source|
        text = source_text(card, source)
        next [] if text.blank?

        tagger.spans(text, category: category.name, source: source, attributes: names).filter_map do |span|
          next if Reference::NAMING.include?(span.attribute) && Text.after_for?(text, span.start)
          kind = catalog.attributes.fetch(span.attribute).kind
          next if kind.is_a?(Kinds::Color) && kind.negated?(text, position: span.start)
          value = kind.normalize(span.raw, category: category) || (span.raw if TAGGED_AS_WRITTEN.include?(kind.class)) or next

          rule = tagger.rule
          if kind.is_a?(Kinds::Color) && kind.evidence_rule(text, position: span.start, length: span.raw.length, source: source) == "mention"
            rule = "mention"
          end
          Candidate.build(attribute: span.attribute, value: value, raw: span.raw, source: "tagger", rule: rule, origin: text_origin(source, card))
        end
      end
    end

    # What is read of each source. The title without a gift added to it ("… 4/128 GB + Power Bank 10000 mAh as a gift"
    # is not a phone with a 10000 mAh battery); the description without a copy of the title in it, so that the title
    # read twice is not two sources that agree.
    def source_text(card, source)
      return Text.without_gift(card.heading) if source == "title"

      description = card.description.to_s
      heading = card.heading.to_s.strip
      return description if heading.length < 12 || Text.key(description) == Text.key(heading)

      at = description.downcase.index(heading.downcase)
      at ? description.dup.tap { |text| text[at, heading.length] = " " * heading.length } : description
    end

    # A copied title inside the description does not constitute corroboration.
    def text_origin(source, card)
      return "description" if card.title.blank?
      return "title" if source == "title"

      heading = Text.key(card.heading)
      heading.present? && Text.key(card.description) == heading ? "title" : "description"
    end

    def read(attribute, card, category)
      readings = from_seller(attribute, card, category) + TEXT_SOURCES.flat_map do |source|
        attribute.kind.scan(source_text(card, source), category: category, source: source).map do |match|
          Candidate.build(attribute: attribute.name, value: match.value, raw: match.raw, source: source, rule: match.rule, origin: text_origin(source, card))
        end
      end
      unreliable ? readings.filter_map { |reading| unreliable.apply(category.name, reading) } : readings
    end

    # The seller's own fields for the attribute: normalized when they can be read, kept as written when the kind
    # allows. Two fields that say different things are two candidates, and so a reason for review.
    def from_seller(attribute, card, category)
      card.seller_attributes.values_at(*attribute.seller_keys).compact_blank.filter_map do |raw|
        value = attribute.kind.normalize(raw, category: category)
        rule = value ? "key" : "raw"
        value ||= raw if attribute.kind.open?

        Candidate.build(attribute: attribute.name, value: value, raw: raw, source: "seller", rule: rule) if value
      end.uniq(&:value)
    end
  end
end
