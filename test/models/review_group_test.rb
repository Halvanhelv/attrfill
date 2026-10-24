require "test_helper"

class ReviewGroupTest < ActiveSupport::TestCase
  def value(description: "Описание", alternatives: [])
    card = Card.create!(title: "Смартфон Example X", description: description,
                        detected_category: "smartphone", seller_attributes: { "Цвет" => "синий" })
    card.attribute_values.create!(name: "color", value: "синий", extracted_value: "синий", raw: "синий",
                                  status: "review", confidence: 0.9, source: "seller", alternatives: alternatives)
  end

  test "preview groups identical evidence across cards and excludes different context or alternatives" do
    first, second = value, value
    value(description: "Другая комплектация")
    value(alternatives: [ "черный" ])
    preview = ReviewGroup.preview(first)
    assert_equal [ first.id, second.id ], preview[:values].map(&:id)
    result = ReviewGroup.apply(preview[:token], decision: "correct", replacement: "черный")
    assert_equal 2, result[:count]
    assert_equal [ "черный", "corrected", "синий" ], first.reload.attributes.values_at("value", "status", "extracted_value")
    assert_equal "черный", second.reload.to_finding.value
    assert_equal 2, AttributeValue.review.count
    assert_equal 2, ReviewGroup.undo(result[:undo_token])
    assert_equal [ "синий", "review", 0.9 ], first.reload.attributes.values_at("value", "status", "confidence")
    assert_nil first.reviewed_at
    assert_raises(ReviewGroup::Conflict) { ReviewGroup.undo(result[:undo_token]) }
  end

  test "stale preview changes no values" do
    first, second = value, value
    preview = ReviewGroup.preview(first)
    second.correct!("белый")
    assert_raises(ReviewGroup::Conflict) { ReviewGroup.apply(preview[:token], decision: "approve") }
    assert first.reload.review?
    assert_equal "белый", second.reload.value
  end

  test "undo preserves later human decisions and rolls back no partial subset" do
    first, second = value, value
    result = ReviewGroup.apply(ReviewGroup.preview(first)[:token], decision: "approve")
    second.correct!("белый")
    assert_raises(ReviewGroup::Conflict) { ReviewGroup.undo(result[:undo_token]) }
    assert first.reload.approved?
    assert_equal "белый", second.reload.value
  end

  test "changing the card text invalidates a preview" do
    first, second = value, value
    preview = ReviewGroup.preview(first)
    second.card.update!(description: "Новое описание")
    assert_raises(ReviewGroup::Conflict) { ReviewGroup.apply(preview[:token], decision: "approve") }
    assert_equal 2, AttributeValue.review.count
  end

  test "tampered and expired tokens are rejected" do
    first = value
    value
    token = ReviewGroup.preview(first)[:token]
    assert_raises(ReviewGroup::Conflict) { ReviewGroup.apply("#{token}x", decision: "approve") }
    travel 16.minutes do
      assert_raises(ReviewGroup::Conflict) { ReviewGroup.apply(token, decision: "approve") }
    end
    assert_equal 2, AttributeValue.review.count
  end

  test "arriving duplicates are not added after preview" do
    first = value
    value
    token = ReviewGroup.preview(first)[:token]
    later = value
    result = ReviewGroup.apply(token, decision: "approve")
    assert_equal 2, result[:count]
    assert later.reload.review?
  end

  test "single rows and empty group corrections are refused" do
    first = value
    assert_raises(ReviewGroup::Conflict) { ReviewGroup.apply(ReviewGroup.preview(first)[:token], decision: "approve") }
    value
    assert_raises(ReviewGroup::Conflict) do
      ReviewGroup.apply(ReviewGroup.preview(first)[:token], decision: "correct", replacement: " ")
    end
    assert_equal 2, AttributeValue.review.count
  end

  test "preview is limited to one hundred explicit rows" do
    first = value
    100.times { value }
    preview = ReviewGroup.preview(first)
    assert_equal 100, preview[:values].size
    assert_equal 100, ReviewGroup.apply(preview[:token], decision: "approve")[:count]
    assert_equal 1, AttributeValue.review.count
  end

  test "the value a group is opened from is always in it" do
    seed = value
    seed.update_columns(confidence: 0.95)
    600.times { value }
    preview = ReviewGroup.preview(seed)
    assert_equal seed.id, preview[:values].first.id
    assert_equal 1, preview[:values].size
  end
end
