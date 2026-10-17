require "test_helper"

class Extraction::RunnerTest < ActiveSupport::TestCase
  Item = Data.define(:card)

  class CountingPipeline
    attr_reader :calls

    def initialize = @calls = 0

    def call(card)
      @calls += 1
      Extraction::Pipeline::Result.new(card: card, category: nil, findings: [], asked_model: false)
    end
  end

  test "duplicate cards are extracted once while input order and ids are preserved" do
    pipeline = CountingPipeline.new
    first = Item.new(card: Extraction::Card.build(id: "first", title: "Один товар"))
    other = Item.new(card: Extraction::Card.build(id: "other", title: "Другой товар"))
    duplicate = Item.new(card: Extraction::Card.build(id: "duplicate", title: "Один товар"))

    results = Extraction::Runner.new(pipeline: pipeline, threads: 2).each([ first, other, duplicate ]).map do |_item, result|
      result
    end

    assert_equal 2, pipeline.calls
    assert_equal %w[first other duplicate], results.map { |result| result.card.id }
  end

  test "checkpoint mode propagates extraction errors instead of writing empty predictions" do
    pipeline = Object.new
    def pipeline.call(_card) = raise(ArgumentError, "broken extraction")
    row = Struct.new(:card).new(Extraction::Card.build(title: "Test"))
    runner = Extraction::Runner.new(pipeline: pipeline, threads: 1, fail_fast: true)
    previous = Thread.report_on_exception
    Thread.report_on_exception = false
    error = assert_raises(ArgumentError) { runner.each([ row ]).to_a }
    assert_equal "broken extraction", error.message
  ensure
    Thread.report_on_exception = previous
  end
end
