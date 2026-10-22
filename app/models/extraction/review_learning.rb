module Extraction
  # Turns reviewers' decisions into what the pipeline trusts next:
  #   - each decided value counts for its acceptance group (approved: right; corrected to another value or rejected:
  #     wrong), added to the held-out counts the base groups were learned from (config/acceptance-counts.json); groups
  #     that reach AcceptanceGroups' bar and are not base groups are written to config/acceptance-groups-learned.yml;
  #   - approved and corrected values become what people confirmed for that title (Confirmed, config/confirmed.json.gz).
  # Run nightly by LearnFromReviewsJob, or by hand: bin/rails extraction:learn_from_reviews.
  class ReviewLearning
    Summary = Data.define(:decisions, :groups_learned, :confirmed_titles, :shadow, :audit)

    def self.call = new.call

    # policy_root: where the acceptance files are read and written (config/ by default).
    def initialize(policy_root: Rails.root.join("config"))
      @policy_root = Pathname(policy_root)
    end

    def call
      counts = held_out_counts
      decisions = 0
      AttributeValue.where(status: %w[approved corrected rejected]).where.not(evidence: nil).find_each do |value|
        verdict = value.verdict
        next if verdict.nil?

        decisions += 1
        counts[value.evidence][0] += 1
        counts[value.evidence][1] += 1 if verdict
      end

      base = AcceptanceGroups.load(@policy_root.join("acceptance-groups.yml"))&.to_h || {}
      learned = AcceptanceGroups.new(AcceptanceGroups.build(counts).to_h.except(*base.keys))
      learned.save(@policy_root.join("acceptance-groups-learned.yml"))

      confirmed = Confirmed.build(confirmed_records)
      confirmed.save(Extraction.config_path("confirmed.json.gz"))
      Extraction.reload!

      Summary.new(decisions: decisions, groups_learned: learned.to_h.size, confirmed_titles: confirmed.size,
                  shadow: measured("shadow"), audit: measured("audit"))
    end

    private

    def held_out_counts
      counts = Hash.new { |hash, signature| hash[signature] = [ 0, 0 ] }
      path = @policy_root.join("acceptance-counts.json")
      JSON.parse(path.read).each { |signature, (labelled, right)| counts[signature] = [ labelled, right ] } if path.exist?
      counts
    end

    def confirmed_records
      AttributeValue.where(status: %w[approved corrected]).where.not(value: [ nil, "" ]).includes(:card).find_each.map do |value|
        [ value.card.title, value.name, value.value ]
      end
    end

    # How the values a policy would have published fared with reviewers: [decided, right].
    def measured(note)
      verdicts = AttributeValue.where(note: note, status: %w[approved corrected rejected]).map(&:verdict).compact
      [ verdicts.size, verdicts.count(true) ]
    end
  end
end
