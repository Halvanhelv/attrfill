require "test_helper"

class WorkEstimateTest < ActiveSupport::TestCase
  test "remaining work includes missing values, quality control and fixes, and can exceed manual work" do
    estimate = WorkEstimate.new(values: 3600, review_share: 0.1, missing_share: 0.2, accepted_error_rate: 0.01,
                                manual_seconds: 5, review_seconds: 5, missing_seconds: 30, qa_share: 0.1,
                                fix_seconds: 100, hourly_rate: 500)
    assert_equal 5, estimate.manual_hours
    assert_in_delta 2520, estimate.accepted
    assert_in_delta 0.35, estimate.qa_hours
    assert_in_delta 0.7, estimate.fix_hours
    assert_in_delta 7.55, estimate.remaining_hours
    assert_in_delta(-1275, estimate.labor_savings)
    assert_operator estimate.break_even_review_seconds, :<, 0
  end

  test "break-even review time makes the estimate zero" do
    estimate = WorkEstimate.new(values: 1000, review_share: 0.65, missing_share: 0.163, accepted_error_rate: 0.004,
                                manual_seconds: 20, review_seconds: 6, missing_seconds: 20, qa_share: 0.05, fix_seconds: 120)
    even = WorkEstimate.new(values: 1000, review_share: 0.65, missing_share: 0.163, accepted_error_rate: 0.004,
                            manual_seconds: 20, review_seconds: estimate.break_even_review_seconds, missing_seconds: 20,
                            qa_share: 0.05, fix_seconds: 120)
    assert_in_delta 0, even.saved_hours, 1e-9
  end

  test "default shares come from a report of the mode in force only" do
    report = { "acceptance_mode" => "strict", "cards" => 10, "attributes" => {
      "brand" => { "gold" => 10, "accepted" => 4, "accepted_correct" => 3, "review" => 5, "missing" => 1 } } }
    assert_equal({ review_share: 0.5, missing_share: 0.1, accepted_error_rate: 0.25 }, WorkEstimate.measured_shares(report, "strict"))
    assert_nil WorkEstimate.measured_shares(report, "standard")
    assert_equal 0.136, WorkEstimate.defaults(report, mode: "standard")[:review_share]
    assert_equal 0.547, WorkEstimate.defaults(nil, mode: "strict")[:review_share]
  end

  test "invalid shares and nonfinite numbers are rejected" do
    assert_raises(ArgumentError) { WorkEstimate.new(review_share: 0.8, missing_share: 0.3) }
    assert_raises(ArgumentError) { WorkEstimate.new(values: "NaN") }
    assert_raises(ArgumentError) { WorkEstimate.new(review_seconds: -1) }
    assert_raises(ArgumentError) { WorkEstimate.new(qa_share: 1.5) }
  end

  test "uncertainty bound does not certify a tiny error free sample" do
    assert_operator Evaluation.precision_lower_bound(20, 20), :<, 0.99
    assert_operator Evaluation.precision_lower_bound(1000, 1000), :>, 0.99
    assert_equal 0, Evaluation.precision_lower_bound(0, 0)
  end
end
