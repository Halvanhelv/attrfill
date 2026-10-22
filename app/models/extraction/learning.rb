require "zlib"

module Extraction
  # What the pipeline publishes beyond the strict policy, from what held-out cards and reviewers taught it.
  #
  # Every final value is labelled with its acceptance group (Finding#evidence), so each reviewer's decision counts for
  # that group. A value is published when its group is trusted:
  #   base:    groups held-out labelled cards proved (config/acceptance-groups.yml);
  #   learned: groups reviewers' decisions proved since (config/acceptance-groups-learned.yml), and values people
  #            confirmed TRUSTED times for the same title with nothing on the card disagreeing.
  # Learned trust is applied only in mode "on"; in "shadow" such values stay in review, noted "shadow", so the policy is
  # measured on reviewers' decisions before it publishes anything. A share of the values a policy would publish
  # (audit_share) still goes to review, noted "audit", so a trusted group keeps being measured.
  # Settings: config/acceptance.yml, section learning. Strict mode only; ACCEPTANCE_GROUPS=off turns it off.
  class Learning
    MODES = %w[off shadow on].freeze
    DIRECT = %w[seller title description tagger].freeze

    def self.current
      return @current if defined?(@current)

      settings = Acceptance.policy.fetch("learning", {})
      @current = if Acceptance.mode == "strict" && ENV["ACCEPTANCE_GROUPS"] != "off"
        new(base: AcceptanceGroups.load(Rails.root.join("config/acceptance-groups.yml")),
            learned: AcceptanceGroups.load(Rails.root.join("config/acceptance-groups-learned.yml")),
            mode: settings.fetch("mode", "shadow"), audit_share: settings.fetch("audit_share", 0.0))
      end
    end

    def self.reset!
      remove_instance_variable(:@current) if defined?(@current)
    end

    attr_reader :mode

    def initialize(base: nil, learned: nil, mode: "shadow", audit_share: 0.0)
      raise ArgumentError, "Unknown learning mode #{mode}" unless MODES.include?(mode.to_s)

      @base = base
      @learned = learned
      @mode = mode.to_s
      @audit_share = audit_share.to_f
    end

    def call(findings, candidates, catalog:, category:, card:)
      by_attribute = candidates.group_by(&:attribute)
      findings.map do |finding|
        next finding if finding.missing?

        attribute = catalog.attributes.fetch(finding.attribute)
        readings = by_attribute.fetch(finding.attribute, [])
        finding = finding.with(evidence: AcceptanceGroups.signature(category, attribute, finding.value, readings))
        next finding unless finding.review?

        case trust(finding, attribute, readings)
        when :base then publish(finding, card)
        when :learned
          next finding if mode == "off"
          mode == "on" ? publish(finding, card) : finding.with(note: "shadow")
        else finding
        end
      end
    end

    private

    def trust(finding, attribute, readings)
      return :base if @base&.include?(finding.evidence)
      :learned if @learned&.include?(finding.evidence) || confirmed?(finding, attribute, readings)
    end

    # People confirmed this value for the same title often enough, and nothing read on the card says otherwise.
    def confirmed?(finding, attribute, readings)
      agreeing, rivals = readings.partition { |reading| attribute.kind.same?(finding.value, reading.value) }
      agreeing.any? { |reading| reading.source == "confirmed" && reading.rule == "confirmed" } &&
        rivals.none? { |reading| DIRECT.include?(reading.source) }
    end

    def publish(finding, card)
      audited?(card, finding) ? finding.with(note: "audit") : finding.with(status: "accepted")
    end

    # The same card and attribute is always sampled the same way.
    def audited?(card, finding)
      @audit_share.positive? && Zlib.crc32("#{card.heading}|#{finding.attribute}") % 10_000 < @audit_share * 10_000
    end
  end
end
