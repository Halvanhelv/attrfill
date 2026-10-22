require "test_helper"

module Extraction
  class LearningTest < ActiveSupport::TestCase
    TITLE = "Ноутбук ASUS Vivobook 15 X1504ZA".freeze

    # The strict policy holds these values back; Learning is what publishes them.
    setup { @mode, ENV["ACCEPTANCE_MODE"] = ENV["ACCEPTANCE_MODE"], "strict" }
    teardown { ENV["ACCEPTANCE_MODE"] = @mode }

    def pipeline(learning, confirmed: nil)
      Pipeline.new(llm: nil, tagger: nil, reference: nil, prior: nil, context: nil, unreliable: nil, confirmed: confirmed, learning: learning)
    end

    def brand_group = "laptop/brand/title/alone"

    test "labels every value with its group and publishes base groups" do
      result = pipeline(Learning.new(base: AcceptanceGroups.new(brand_group => [ 300, 300 ]))).call(card(title: TITLE, category: "Ноутбуки"))

      assert_equal brand_group, result["brand"].evidence
      assert_equal "accepted", result["brand"].status
    end

    test "a group learned from reviews only notes its values in shadow mode, publishes them when on, ignores them when off" do
      learned = AcceptanceGroups.new(brand_group => [ 300, 300 ])

      shadow = pipeline(Learning.new(learned: learned, mode: "shadow")).call(card(title: TITLE, category: "Ноутбуки"))
      on = pipeline(Learning.new(learned: learned, mode: "on")).call(card(title: TITLE, category: "Ноутбуки"))
      off = pipeline(Learning.new(learned: learned, mode: "off")).call(card(title: TITLE, category: "Ноутбуки"))

      assert_equal %w[review shadow], [ shadow["brand"].status, shadow["brand"].note ]
      assert_equal [ "accepted", nil ], [ on["brand"].status, on["brand"].note ]
      assert_equal [ "review", nil ], [ off["brand"].status, off["brand"].note ]
    end

    test "sends a sample of publishable values to review as an audit" do
      learning = Learning.new(base: AcceptanceGroups.new(brand_group => [ 300, 300 ]), audit_share: 1.0)

      result = pipeline(learning).call(card(title: TITLE, category: "Ноутбуки"))

      assert_equal %w[review audit], [ result["brand"].status, result["brand"].note ]
    end

    test "values people confirmed enough times for the same title, colour aside, are trusted; once is only a suggestion" do
      twice = Confirmed.build(%w[черный серый белый].map { |color| [ "Ноутбук ASUS Vivobook 15 X1504ZA #{color}", "ram", "16 ГБ" ] })
      once = Confirmed.build([ [ "Ноутбук ASUS Vivobook 15 X1504ZA черный", "ram", "16 ГБ" ] ])
      learning = Learning.new(mode: "on")

      trusted = pipeline(learning, confirmed: twice).call(card(title: "#{TITLE} белый", category: "Ноутбуки"))
      suggested = pipeline(learning, confirmed: once).call(card(title: "#{TITLE} белый", category: "Ноутбуки"))

      assert_equal %w[16\ ГБ confirmed accepted], [ trusted["ram"].value, trusted["ram"].source, trusted["ram"].status ]
      assert_equal %w[16\ ГБ review], [ suggested["ram"].value, suggested["ram"].status ]
    end

    test "people disagreeing on a value, or the card saying otherwise, keeps it in review" do
      split = Confirmed.build([ [ TITLE, "ram", "16 ГБ" ], [ TITLE, "ram", "8 ГБ" ] ])
      agreed = Confirmed.build([ [ TITLE, "ram", "16 ГБ" ] ] * 3)
      learning = Learning.new(mode: "on")

      assert pipeline(learning, confirmed: split).call(card(title: TITLE, category: "Ноутбуки"))["ram"].missing?
      contradicted = pipeline(learning, confirmed: agreed).call(card(title: "#{TITLE} 8/512 ГБ", category: "Ноутбуки"))
      assert_equal "8 ГБ", contradicted["ram"].value
      assert_not contradicted["ram"].accepted? && contradicted["ram"].source == "confirmed"
    end
  end
end
