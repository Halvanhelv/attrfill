class MetricsController < ApplicationController
  def show
    report = Evaluation.last
    inputs = params.permit(*WorkEstimate::INPUTS).to_h.symbolize_keys.compact_blank
    estimate = WorkEstimate.new(**WorkEstimate.defaults(report).merge(inputs))
  rescue ArgumentError, TypeError
    redirect_to metrics_path, alert: "Enter non-negative numbers; shares go from 0 to 1, and the review and miss shares together may not exceed 1."
  else
    render locals: { report: report, benchmark: f1_benchmark, by_source: AttributeValue.where.not(source: nil).group(:source).count,
                     estimate: estimate, estimate_source: WorkEstimate.source(report),
                     by_status: AttributeValue.group(:status).count, cards: Card.count,
                     asked_model: Card.where(asked_model: true).count,
                     llm: LlmCall.pick(Arel.sql("COUNT(*), COALESCE(SUM(input_tokens), 0), COALESCE(SUM(output_tokens), 0), COALESCE(AVG(duration_ms), 0)")) }
  end

  private

  def f1_benchmark
    path = Rails.root.join("results/f1-max/summary.json")
    JSON.parse(path.read) if path.file?
  rescue JSON::ParserError
    nil
  end
end
