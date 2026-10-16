module Extraction
  # How often a value found this way is right. Measured on labelled data when config/calibration.yml exists
  # (`bin/rails extraction:learn`), a prior by source and rule until then.
  module Confidence
    SOURCE = { "seller" => 0.95, "title" => 0.9, "description" => 0.82, "tagger" => 0.75, "confirmed" => 0.97, "reference" => 0.85, "llm" => 0.8,
               "prior" => 0.5 }.freeze

    # A rule weaker than its source: a bare "8 GB" may be either memory, a model name is cut by guesswork.
    RULE = { "bare" => 0.85, "combo_unitless" => 0.92, "raw" => 0.85, "product_line" => 0.92,
             "after_brand" => 0.9, "after_brand_plain" => 0.7, "ungrounded" => 0.5, "compatibility" => 0.4, "mention" => 0.5,
             "fuzzy" => 0.8, "position" => 0.7, "after_guess" => 0.7,
             "single" => 0.9, "majority" => 0.9, "code" => 0.85, "family" => 0.7, "component_sum" => 0.8,
             "unreliable" => 0.8, "confirmed_once" => 0.9 }.freeze

    module_function

    def of(attribute, source, rule)
      calibration["#{attribute}/#{source}/#{rule}"] || (SOURCE.fetch(source) * RULE.fetch(rule, 1.0)).round(3)
    end

    def calibration
      @calibration ||= begin
        path = Extraction.config_path("calibration.yml")
        path.exist? ? (YAML.load_file(path) || {}) : {}
      end
    end

    def reset! = @calibration = nil
  end
end
