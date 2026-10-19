ENV["RAILS_ENV"] ||= "test"
ENV.delete("LLM_API_KEY")
# Most existing tests exercise extraction rules at their historical threshold.
ENV["ACCEPTANCE_MODE"] = "standard"
require_relative "../config/environment"
require "rails/test_help"

# Tests read the hand-written config only, not what bin/learn last learned from a dataset.
Rails.root.join("tmp/test_config").then do |root|
  FileUtils.rm_rf(root)
  FileUtils.cp_r(Rails.root.join("config"), root)
  %w[calibration.yml formats.yml unreliable.yml confirmed.json.gz reference.json.gz prior.json.gz context.json.gz tagger dictionaries/learned dictionaries/catalog].each { |learned| FileUtils.rm_rf(root.join(learned)) }
  Dir[root.join("catalog.*.yml")].each { |generated| FileUtils.rm_f(generated) }
  Extraction.config_root = root
  Extraction.reload!
end
Dir[Rails.root.join("test/support/**/*.rb")].each { |file| require file }

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    def card(**fields) = Extraction::Card.build(**fields)

    # Rules only, unless a test hands a tagger, known products or a model in.
    def extract(llm: nil, tagger: nil, reference: nil, prior: nil, **fields)
      Extraction::Pipeline.new(llm: llm, tagger: tagger, reference: reference, prior: prior).call(card(**fields))
    end

    def values(result) = result.findings.reject(&:missing?).to_h { |finding| [ finding.attribute, finding.value ] }
  end
end
