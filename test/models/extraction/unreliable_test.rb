require "test_helper"

module Extraction
  class UnreliableTest < ActiveSupport::TestCase
    test "learns which values a rule reads are mostly wrong in a category, and what they stand for" do
      unreliable = Unreliable.build(
        "tv/screen_type/description" => { "LED" => [ 30, 1, { "VA" => 20, "IPS" => 9, "LED" => 1 } ], "OLED" => [ 30, 29, { "OLED" => 29 } ] },
        "monitor/screen_diagonal/title" => { "24\"" => [ 25, 2, { "23.8\"" => 23, "24\"" => 2 } ] }
      )

      assert_equal({ "LED" => nil }, unreliable.to_h["tv/screen_type/description"])
      assert_equal({ "24\"" => "23.8\"" }, unreliable.to_h["monitor/screen_diagonal/title"])
    end

    test "too few readings teach nothing" do
      assert_empty Unreliable.build("tv/screen_type/description" => { "LED" => [ 5, 0, { "VA" => 5 } ] }).to_h
    end

    test "a pipeline drops the value or reads it as what it stands for, and keeps other sources" do
      unreliable = Unreliable.new("monitor/screen_diagonal/title" => { "24\"" => "23.8\"" }, "tv/screen_type/description" => { "LED" => nil })
      pipeline = Pipeline.new(llm: nil, tagger: nil, reference: nil, prior: nil, context: nil, unreliable: unreliable)

      monitor = pipeline.call(card(title: "Монитор Samsung S24D300 24\""))
      assert_equal "23.8\"", monitor["screen_diagonal"].value
      assert_equal "unreliable", monitor["screen_diagonal"].rule

      tv = pipeline.call(card(title: "Телевизор Hi 43\" VHIX-43U169", description: "LED подсветка"))
      assert tv["screen_type"].missing?
    end
  end
end
