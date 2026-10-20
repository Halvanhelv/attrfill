# Hours of people's work with and without the system, for a number of attribute values.
# The shares come from a measurement (an evaluation report of the same acceptance mode); the seconds are
# assumptions until measured in a timed session (docs/independent-review.md, "Timing protocol").
#
# Without the system a person fills every value: values × manual_seconds.
# With it: every value sent to review is checked (review_seconds); every value it did not find is filled by hand
# as before (missing_seconds, by default the same as manual work); a sample of the accepted values is checked
# (qa_share); and every wrongly accepted value costs its fix after publication (fix_seconds).
class WorkEstimate
  INPUTS = %i[values review_share missing_share accepted_error_rate manual_seconds review_seconds missing_seconds
              qa_share fix_seconds hourly_rate].freeze

  # Unseen products of the case (test_new: 1 455 cards, 7 854 labelled values, models learned on the training
  # part only, LLM off, 23.10.2026), used when the app has no evaluation of the acceptance mode in force.
  DIAGNOSTIC = {
    "strict" => { review_share: 0.547, missing_share: 0.249, accepted_error_rate: 0.009 },
    "standard" => { review_share: 0.136, missing_share: 0.248, accepted_error_rate: 0.051 }
  }.freeze

  ASSUMED = { values: 100_000, manual_seconds: 20, review_seconds: 6, missing_seconds: 20, qa_share: 0.05,
              fix_seconds: 120, hourly_rate: 500 }.freeze

  attr_reader(*INPUTS)

  # Shares of labelled values from the report when it was made in the mode in force, else the diagnostic run.
  def self.defaults(report, mode: Extraction::Acceptance.mode)
    ASSUMED.merge(measured_shares(report, mode) || DIAGNOSTIC.fetch(mode))
  end

  def self.measured_shares(report, mode)
    return unless report && report["acceptance_mode"] == mode

    counts = report["attributes"].values
    gold = counts.sum { |count| count["gold"].to_i }
    accepted = counts.sum { |count| count["accepted"].to_i }
    return if gold.zero?

    { review_share: (counts.sum { |count| count["review"].to_i }.to_f / gold).round(3),
      missing_share: (counts.sum { |count| count["missing"].to_i }.to_f / gold).round(3),
      accepted_error_rate: accepted.zero? ? 0.0 : (1 - counts.sum { |count| count["accepted_correct"].to_i }.to_f / accepted).round(4) }
  end

  # Where the default shares come from, in words.
  def self.source(report, mode: Extraction::Acceptance.mode)
    if measured_shares(report, mode)
      "this app's saved measurement (#{report["cards"]} cards, #{mode} mode)"
    else
      "the pilot's measurement on new products of Oct 23, 2026 (1,455 cards, #{mode} mode); the app has no measurement of this mode"
    end
  end

  def initialize(**inputs)
    inputs = ASSUMED.merge(DIAGNOSTIC.fetch("strict")).merge(inputs.compact)
    INPUTS.each do |name|
      value = Float(inputs.fetch(name))
      raise ArgumentError, "Invalid value: #{name}" unless value.finite? && value >= 0

      instance_variable_set("@#{name}", value)
    end
    raise ArgumentError, "The shares must add up to no more than 100%" if review_share + missing_share > 1
    raise ArgumentError, "The error and QA shares must be between 0 and 1" if accepted_error_rate > 1 || qa_share > 1
  end

  def accepted_share = 1 - review_share - missing_share
  def accepted = values * accepted_share

  def manual_hours = values * manual_seconds / 3600
  def review_hours = values * review_share * review_seconds / 3600
  def missing_hours = values * missing_share * missing_seconds / 3600
  def qa_hours = accepted * qa_share * review_seconds / 3600
  def fix_hours = accepted * accepted_error_rate * fix_seconds / 3600
  def published_errors = accepted * accepted_error_rate
  def remaining_hours = review_hours + missing_hours + qa_hours + fix_hours
  def saved_hours = manual_hours - remaining_hours
  def labor_savings = saved_hours * hourly_rate

  # The seconds per checked suggestion at which the system saves nothing; nil when nothing goes to review.
  def break_even_review_seconds
    checked = values * (review_share + accepted_share * qa_share)
    return if checked.zero?

    (manual_hours - missing_hours - fix_hours) * 3600 / checked
  end
end
