require "test_helper"

class Extraction::ResolverTest < ActiveSupport::TestCase
  test "direct text beats a conflicting reference even with lower confidence" do
    attribute = Extraction::Catalog.current.attributes.fetch("color")
    direct = Extraction::Candidate.new(attribute: "color", value: "черный", raw: "Black", source: "title",
                                       rule: "dictionary", confidence: 0.6)
    reference = Extraction::Candidate.new(attribute: "color", value: "серый", raw: "серый", source: "reference",
                                          rule: "majority", confidence: 0.9)

    finding = Extraction::Resolver.resolve(attribute, [ reference, direct ])

    assert_equal [ "черный", "title", [ "серый" ] ], [ finding.value, finding.source, finding.alternatives ]
    assert finding.review?
  end
end
