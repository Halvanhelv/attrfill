require "test_helper"

module Extraction
  class AcceptanceGroupsTest < ActiveSupport::TestCase
    test "keeps groups right often enough on enough labelled values, never a guess alone" do
      groups = AcceptanceGroups.build(
        "laptop/brand/title/alone" => [ 300, 300 ],
        "laptop/ram/title/alone" => [ 300, 270 ],
        "laptop/storage/title/alone" => [ 20, 20 ],
        "tv/color/prior/alone" => [ 500, 500 ],
        "tv/color/reference?/alone" => [ 500, 500 ]
      )

      assert_equal [ "laptop/brand/title/alone" ], groups.to_h.keys
    end

    test "publishes a final value of a trusted group the strict gates held back" do
      signature = AcceptanceGroups.signature("laptop", Catalog.current.attributes.fetch("brand"), "ASUS",
                                             [ Candidate.build(attribute: "brand", value: "ASUS", raw: "ASUS", source: "title", rule: "dictionary") ])
      learning = Learning.new(base: AcceptanceGroups.new(signature => [ 300, 300 ]))
      pipeline = Pipeline.new(llm: nil, tagger: nil, reference: nil, prior: nil, context: nil, unreliable: nil, confirmed: nil, learning: learning)

      result = pipeline.call(card(title: "Ноутбук ASUS Vivobook 15 X1504ZA", category: "Ноутбуки"))

      assert_equal "laptop/brand/title/alone", signature
      assert_equal "accepted", result["brand"].status
      assert_equal signature, result["brand"].evidence
    end
  end
end
