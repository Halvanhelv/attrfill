require "test_helper"

class ReviewLearningTest < ActiveSupport::TestCase
  setup do
    @root = Pathname(Dir.mktmpdir)
    @root.join("acceptance-groups.yml").write({ "laptop/brand/title/alone" => [ 300, 300 ] }.to_yaml)
    @root.join("acceptance-counts.json").write({ "laptop/ram/title/alone" => [ 40, 40 ] }.to_json)
  end

  teardown { FileUtils.rm_rf(@root) }

  def decided(title, name, extracted, status, value: extracted, evidence: "laptop/#{name}/title/alone")
    card = Card.create!(title: title, detected_category: "laptop")
    card.attribute_values.create!(name: name, value: value, extracted_value: extracted, status: status, confidence: 1.0,
                                  source: "title", evidence: evidence, reviewed_at: Time.current)
  end

  test "adds reviewers' decisions to the held-out counts and learns the groups that reach the bar" do
    20.times { |index| decided("Ноутбук ASUS #{index}", "ram", "16 ГБ", "approved") }
    decided("Ноутбук ASUS 99", "storage", "512 ГБ", "corrected", value: "1 ТБ")

    summary = Extraction::ReviewLearning.new(policy_root: @root).call

    assert_equal 21, summary.decisions
    assert_equal [ "laptop/ram/title/alone" ], YAML.load_file(@root.join("acceptance-groups-learned.yml")).keys
  end

  test "remembers approved and corrected values per title and measures shadow decisions" do
    value = decided("Ноутбук ASUS Vivobook 15 X1504ZA черный", "ram", "8 ГБ", "corrected", value: "16 ГБ")
    value.update!(note: "shadow")

    summary = Extraction::ReviewLearning.new(policy_root: @root).call
    found = Extraction::Confirmed.current.candidates(Extraction::Card.build(title: "Ноутбук ASUS Vivobook 15 X1504ZA белый"),
                                                     [ Extraction::Catalog.current.attributes.fetch("ram") ])

    assert_equal [ "16 ГБ" ], found.map(&:value)
    assert_equal [ 1, 0 ], summary.shadow
  end

  test "a value no one offered says nothing about a group" do
    assert_nil AttributeValue.new(name: "ram", extracted_value: nil, value: "16 ГБ", status: "corrected").verdict
    assert_equal true, AttributeValue.new(name: "ram", extracted_value: "16 ГБ", value: "16 ГБ", status: "corrected").verdict
    assert_equal false, AttributeValue.new(name: "ram", extracted_value: "8 ГБ", value: nil, status: "rejected").verdict
  end
end
