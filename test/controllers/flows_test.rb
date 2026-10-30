require "test_helper"

class FlowsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "strict API keeps a single seller filter reading for review" do
    previous = ENV["ACCEPTANCE_MODE"]
    ENV["ACCEPTANCE_MODE"] = "strict"
    post api_extraction_path, params: { title: "Смартфон Samsung A15", attributes: { "Цвет" => "черный" } }, as: :json
    assert_response :success
    body = response.parsed_body
    color = body["attributes"].find { |value| value["attribute"] == "color" }
    assert_equal "strict", body["acceptance_mode"]
    assert_equal "review", color["status"]
    assert color["needs_review"]
    assert_equal "черный", color["raw"]
  ensure
    ENV["ACCEPTANCE_MODE"] = previous
  end

  test "API refuses malformed and oversized batches rather than silently losing cards" do
    [ "invalid", [ "invalid" ], Array.new(501) { {} } ].each do |cards|
      post api_extraction_path, params: { cards: cards }, as: :json
      assert_response :unprocessable_entity
      assert response.parsed_body["error"].present?
    end
  end

  test "metrics shows scenario economics and validates inputs" do
    get metrics_path, params: { values: 3600, review_share: 0.1, missing_share: 0.2, accepted_error_rate: 0.01,
                               manual_seconds: 5, review_seconds: 5, missing_seconds: 30, qa_share: 0.1,
                               fix_seconds: 100, hourly_rate: 500 }
    assert_response :success
    assert_select "h2", text: "How much manual work is left"
    assert_select "dd", text: /-1.?275/
    assert_select "p", text: /Break-even point/

    get metrics_path
    assert_response :success
    assert_select "input[name=review_share][value='0.136']" # test_helper runs the standard mode

    get metrics_path, params: { review_share: 0.9, missing_share: 0.9 }
    assert_redirected_to metrics_path
  end

  test "a card is pasted and its attributes are shown" do
    get root_path
    assert_response :success

    post cards_path, params: { card: { title: "Смартфон Samsung Galaxy S24 8/256GB", description: "Также есть версия на 128 ГБ" } }
    follow_redirect!

    assert_select "td [data-value]", text: "Galaxy S24"
    assert_select "span", text: "Needs review"
    assert_select "span", text: /another possible answer: 128 ГБ/
  end

  test "a derived refrigerator volume is explained as a sum" do
    post cards_path, params: { card: { title: "Холодильник Example", description: "Холодильная камера 215 л. Морозильная камера 95 л." } }
    follow_redirect!

    assert_response :success
    assert_select "td [data-value]", text: "310 л"
    assert_select "span", text: /Sum of the fridge and freezer compartment volumes/
  end

  test "a file is processed, reviewed and downloaded with the correction in it" do
    perform_enqueued_jobs do
      post batches_path, params: { file: fixture_file_upload(Rails.root.join("data/sample/edge_cases.csv"), "text/csv") }
    end

    batch = Batch.sole
    assert_equal [ "done", 10 ], [ batch.status, batch.cards_count ]

    get batch_path(batch)
    assert_response :success

    value = batch.attribute_values.waiting.find_by!(name: "storage")
    get reviews_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(value)}"

    patch review_path(value), params: { decision: "correct", value: "512gb" }, as: :turbo_stream
    assert_equal [ "corrected", "512 ГБ", 1.0 ], value.reload.then { |one| [ one.status, one.value, one.confidence ] }

    get download_batch_path(batch, format: :csv)
    assert_includes response.body, "storage,512 ГБ,1.0,accepted"

    get download_batch_path(batch, format: :json)
    assert_equal 10, response.parsed_body.size
  end

  test "review approves and rejects" do
    card = Card.extract!(title: "Смартфон Samsung Galaxy S24 8/256GB", description: "Версия на 128 ГБ")
    value = card.attribute_values.find_by!(name: "storage")

    patch review_path(value), params: { decision: "approve" }
    assert value.reload.approved?

    patch review_path(value), params: { decision: "reject" }
    assert_equal [ "rejected", nil ], [ value.reload.status, value.value ]
    assert card.to_result["storage"].missing?
  end

  test "missing values are visible and can be filled by a reviewer" do
    card = Card.extract!(title: "Смартфон")
    value = card.attribute_values.find_by!(name: "brand")

    assert value.missing?
    assert_includes AttributeValue.waiting, value

    get reviews_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(value)}", text: /Brand: —/

    patch review_path(value), params: { decision: "correct", value: "Samsung" }
    assert_equal [ "corrected", "Samsung", 1.0 ], value.reload.then { |one| [ one.status, one.value, one.confidence ] }
    assert_not_includes AttributeValue.waiting, value
  end

  test "confirming an empty field exports it as missing, not as an accepted blank" do
    card = Card.create!(title: "Чехол на Samsung Galaxy S24", detected_category: "generic")
    value = card.attribute_values.create!(name: "brand", value: nil, status: "missing", confidence: 0.0)

    patch review_path(value), params: { decision: "approve", seen: value.version }
    assert_equal [ "rejected", nil ], [ value.reload.status, value.value ]
    assert card.to_result["brand"].missing?
  end

  test "an upload without a file and a file that cannot be read" do
    post batches_path
    assert_redirected_to batches_path

    broken = Rails.root.join("tmp/broken-#{SecureRandom.hex(4)}.json").tap { |path| path.write("# not json") }
    perform_enqueued_jobs { post batches_path, params: { file: fixture_file_upload(broken, "application/json") } }
    broken.delete

    assert Batch.sole.failed?
    get batch_path(Batch.sole)
    assert_select "p", text: /ParserError/
  end

  test "the API answers for one card and for many" do
    post api_extraction_path, params: { title: "Телевизор LG 55UR78006LK 55\" 4K", attributes: { "Цвет" => "чёрный" } }, as: :json

    body = response.parsed_body
    assert_equal "tv", body["category"]
    assert_equal({ "attribute" => "color", "title" => "Color", "value" => "черный", "confidence" => 0.95, "status" => "accepted",
                   "source" => "seller", "raw" => "черный", "rule" => "key", "alternatives" => [],
                   "needs_review" => false }, body["attributes"].find { |attribute| attribute["attribute"] == "color" })
    assert_equal "standard", body["acceptance_mode"]

    post api_extraction_path, params: { cards: [ { id: "a", title: "Смартфон Samsung A15" }, { id: "b", title: "" } ] }, as: :json
    assert_equal %w[a b], response.parsed_body["cards"].pluck("id")
  end

  test "metrics render with and without an evaluation" do
    get metrics_path
    assert_response :success
  end

  test "local ML suggestions remain visible when no external LLM was called" do
    card = Card.create!(title: "Test", detected_category: "smartphone", asked_model: false)
    card.attribute_values.create!(name: "color", value: "черный", extracted_value: "черный",
                                  confidence: 0.75, source: "tagger", status: "review")
    get card_path(card)
    assert_response :success
    assert_select "span", text: "No requests to an external LLM"
    assert_select "span", text: "Initial hints from the trained model: 1"
    assert_no_match "Without a neural network", response.body
    get metrics_path
    assert_response :success
    assert_select "span", text: "trained extraction model"
    assert_select "h2", text: "External LLM usage"
    assert_select "h2", text: "Historical results on the pilot data"
  end

  test "a duplicate group can be previewed corrected and undone" do
    values = 2.times.map do
      card = Card.create!(title: "Same phone", description: "Синий корпус", detected_category: "smartphone")
      card.attribute_values.create!(name: "color", value: "синий", status: "review", source: "title", confidence: 0.9)
    end
    get review_group_path(values.first)
    assert_response :success
    assert_select "a", text: /Card #/, count: 2
    token = css_select('input[name="token"]').sole["value"]
    post review_groups_path, params: { token: token, decision: "correct", value: "черный" }
    assert_response :success
    assert_equal [ "черный", "черный" ], values.map { |value| value.reload.to_finding.value }
    undo_token = css_select('input[name="token"]').sole["value"]
    post undo_review_groups_path, params: { token: undo_token }
    assert_redirected_to reviews_path
    assert values.all? { |value| value.reload.review? && value.value == "синий" }
  end

  test "a decision made on a stale page does not overwrite a later group decision" do
    values = 2.times.map do
      card = Card.create!(title: "Same phone", description: "Синий корпус", detected_category: "smartphone")
      card.attribute_values.create!(name: "color", value: "синий", status: "review", source: "title", confidence: 0.9)
    end
    get reviews_path
    seen = css_select("##{ActionView::RecordIdentifier.dom_id(values.first)} input[name='seen']").sole["value"]
    assert_equal values.first.version, seen

    token = ReviewGroup.preview(values.first)[:token]
    ReviewGroup.apply(token, decision: "correct", replacement: "черный")

    patch review_path(values.first), params: { decision: "reject", seen: seen }, as: :turbo_stream
    assert_response :conflict
    assert_equal [ "corrected", "черный" ], values.first.reload.attributes.values_at("status", "value")

    patch review_path(values.first), params: { decision: "correct", value: "белый", seen: seen }
    assert_redirected_to reviews_path
    assert_match "Another reviewer", flash[:alert]
    assert_equal "черный", values.first.reload.value

    patch review_path(values.first), params: { decision: "correct", value: "белый", seen: values.first.version },
                                     as: :turbo_stream
    assert_response :success
    assert_equal "белый", values.first.reload.value
  end

  test "empty cards, oversized files and malformed JSON are refused with a reason" do
    assert_no_difference "Card.count" do
      post cards_path, params: { card: { title: " ", description: "" } }
    end
    assert_redirected_to new_card_path
    assert_match "empty card", flash[:alert]

    post api_extraction_path, params: +"{\"title\": ", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :bad_request
    assert_equal "The request body is not valid JSON", response.parsed_body["error"]

    limit = Batch::MAX_BYTES
    silence_warnings { Batch.const_set(:MAX_BYTES, 10) }
    assert_no_difference "Batch.count" do
      post batches_path, params: { file: fixture_file_upload(Rails.root.join("data/sample/edge_cases.csv"), "text/csv") }
    end
    assert_redirected_to batches_path
    assert_match "Split it", flash[:alert]
  ensure
    silence_warnings { Batch.const_set(:MAX_BYTES, limit) } if limit
  end
end
