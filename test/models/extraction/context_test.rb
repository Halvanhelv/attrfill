require "test_helper"
require "tmpdir"
require "zlib"

class Extraction::ContextTest < ActiveSupport::TestCase
  setup do
    assert Extraction.const_defined?(:Context), "The optional context predictor is missing"
  end

  def artifact
    { "version" => 1,
      "spaces" => { "title" => { "description_chars" => 0, "features" => [ "t:w:мощный", "t:w:тихий" ], "idf" => [ 1.0, 1.0 ] } },
      "models" => { "vacuum" => { "power" => { "space" => "title", "method" => "linear", "activation" => "softmax",
        "classes" => [ "1000 Вт", "2000 Вт" ], "intercepts" => [ 0.0, 0.0 ],
        "weights" => { "0" => [ -2.0, 2.0 ], "1" => [ 2.0, -2.0 ] }, "threshold" => 0.8,
        "confidence" => 0.7, "replace_prior" => false } } } }
  end

  def context(data = artifact) = Extraction::Context.new(data)
  def category = Extraction::Catalog.current.categories.fetch("vacuum")
  def attributes = [ Extraction::Catalog.current.attributes.fetch("power") ]

  test "linear predictions use normalized text and remain review only" do
    predictor = context
    candidates = predictor.candidates(card(title: "МОЩНЫЙ пылесос Q7"), category, attributes)
    assert_equal [ "2000 Вт" ], candidates.map(&:value)
    assert_equal "prior", candidates.first.source
    assert_equal "context", candidates.first.rule
    assert_equal "unverified_identity", candidates.first.origin
    assert_equal 0.7, candidates.first.confidence
    result = Extraction::Resolver.call(attributes, candidates, category: category.name)
    assert result.first.review?
  end

  test "sparse class coefficients retain the shared score offset" do
    data = artifact
    model = data["models"]["vacuum"]["power"]
    model.merge!("weight_format" => "sparse", "common_weights" => { "0" => -2.0 },
                 "weights" => { "0" => [ [ 1, 4.0 ] ] }, "activation" => "sigmoid_normalize")
    model["threshold"] = 0.8
    assert_equal "2000 Вт", context(data).candidates(card(title: "Мощный"), category, attributes).first.value
    model["threshold"] = 0.9
    assert_empty context(data).candidates(card(title: "Мощный"), category, attributes)
  end

  test "confidence and minimum feature support both gate a prediction" do
    assert_empty context.candidates(card(title: "Неизвестный Q999"), category, attributes)
    data = artifact
    data["models"]["vacuum"]["power"]["threshold"] = 0.999
    assert_empty context(data).candidates(card(title: "Мощный"), category, attributes)
  end

  test "a context suggestion cannot replace an existing prior without a selected policy" do
    prior = Extraction::Candidate.build(attribute: "power", value: "500 Вт", raw: "500 Вт", source: "prior", rule: "vacuum")
    assert_empty context.candidates(card(title: "Мощный"), category, attributes, prior: [ prior ])
    data = artifact
    data["models"]["vacuum"]["power"]["replace_prior"] = true
    assert_equal "2000 Вт", context(data).candidates(card(title: "Мощный"), category, attributes, prior: [ prior ]).first.value
  end

  test "the pipeline fills missing fields but preserves explicit readings and accepted precision" do
    pipeline = Extraction::Pipeline.new(llm: nil, tagger: nil, reference: nil, prior: nil, context: context)
    guessed = pipeline.call(card(title: "Мощный пылесос Q7"))
    assert_equal "2000 Вт", guessed["power"].value
    assert guessed["power"].review?
    explicit = pipeline.call(card(title: "Мощный пылесос Q7, потребляемая мощность 800 Вт"))
    assert_equal "800 Вт", explicit["power"].value
    refute_equal "context", explicit["power"].rule
  end

  test "a context model cannot restore a compatible device identity" do
    data = artifact
    data["models"]["generic"] = { "brand" => data["models"]["vacuum"]["power"].merge("classes" => [ "Apple", "Samsung" ]) }
    generic = Extraction::Catalog.current.generic
    brand = Extraction::Catalog.current.attributes.fetch("brand")
    assert_empty context(data).candidates(card(title: "Мощный чехол для смартфона Samsung"), generic, [ brand ])
  end

  test "cosine neighbours vote only on labelled training examples" do
    data = artifact
    data["spaces"]["title"]["neighbors"] = { "vacuum" => [
      { "values" => { "power" => "2000 Вт" }, "vector" => [ [ 0, 1.0 ] ] },
      { "values" => { "power" => "500 Вт" }, "vector" => [ [ 1, 1.0 ] ] }
    ] }
    data["models"]["vacuum"]["power"].merge!("method" => "knn", "k" => 3, "threshold" => 0.5)
    assert_equal "2000 Вт", context(data).candidates(card(title: "Мощный"), category, attributes).first.value
  end

  test "nonfinite coefficients and invalid vocabulary indices are rejected" do
    data = artifact
    data["models"]["vacuum"]["power"]["intercepts"][0] = Float::INFINITY
    assert_raises(ArgumentError) { context(data) }
    data = artifact
    data["models"]["vacuum"]["power"]["weights"] = { "999" => [ 1.0, -1.0 ] }
    assert_raises(ArgumentError) { context(data) }
  end

  test "malformed neighbor vectors are rejected before inference" do
    data = artifact
    data["spaces"]["title"]["neighbors"] = { "vacuum" => [ { "values" => { "power" => "500 Вт" }, "vector" => [ [ 999, 1.0 ] ] } ] }
    assert_raises(ArgumentError) { context(data) }
  end

  test "valid JSON with invalid nested containers disables only the optional model" do
    Dir.mktmpdir("context-shape-test") do |dir|
      path = Pathname(dir).join("context.json.gz")
      [ artifact.merge("spaces" => nil), artifact.merge("models" => []), artifact.merge("spaces" => { "title" => [] }) ].each do |data|
        path.binwrite(Zlib.gzip(JSON.generate(data)))
        assert_nil Extraction::Context.load(path)
      end
    end
  end

  test "missing malformed or incompatible artifacts preserve the existing pipeline" do
    Dir.mktmpdir("context-model-test") do |dir|
      path = Pathname(dir).join("context.json.gz")
      assert_nil Extraction::Context.load(path)
      path.binwrite("invalid gzip")
      assert_nil Extraction::Context.load(path)
      path.binwrite(Zlib.gzip(JSON.generate(artifact.merge("version" => 99))))
      assert_nil Extraction::Context.load(path)
      path.binwrite(Zlib.gzip(JSON.generate(artifact)))
      assert_instance_of Extraction::Context, Extraction::Context.load(path)
    end
  end
end
