require "zlib"

module Extraction
  # Conditional priors learned from labelled product text. They are suggestions
  # for missing fields, with no claim of literal evidence or automatic approval.
  class Context
    def self.load(path)
      new(JSON.parse(Zlib.gunzip(path.binread))) if path.file?
    rescue JSON::ParserError, Zlib::Error, ArgumentError, KeyError, TypeError => error
      Rails.logger.warn("Context model ignored: #{error.class}")
      nil
    end

    def self.current
      return @current if defined?(@current)

      @current = ENV["CONTEXT"] == "off" ? nil : load(Extraction.config_path("context.json.gz"))
    end

    def self.reset!
      remove_instance_variable(:@current) if defined?(@current)
    end

    def initialize(data)
      raise ArgumentError, "Unsupported context model" unless data.is_a?(Hash) && data["version"] == 1

      raise ArgumentError, "Invalid model containers" unless data["spaces"].is_a?(Hash) && data["models"].is_a?(Hash)

      @spaces = data.fetch("spaces").transform_values { |space| prepare_space(space) }
      @models = data.fetch("models")
      @models.each_value do |attributes|
        raise ArgumentError, "Invalid category models" unless attributes.is_a?(Hash)

        attributes.each_value do |model|
          raise ArgumentError, "Invalid attribute model" unless model.is_a?(Hash)
          raise ArgumentError, "Unknown feature space" unless @spaces.key?(model.fetch("space"))
          raise ArgumentError, "Unknown predictor" unless %w[linear knn].include?(model.fetch("method"))
          raise ArgumentError, "Invalid threshold" unless probability?(model.fetch("threshold")) && probability?(model.fetch("confidence", 0.5))
          if model["method"] == "linear"
            classes = model.fetch("classes")
            raise ArgumentError, "Invalid linear arrays" unless classes.is_a?(Array) && model["intercepts"].is_a?(Array) && model["weights"].is_a?(Hash)

            width = classes.size
            raise ArgumentError, "Invalid classes" if width.zero? || !classes.all? { |label| label.is_a?(String) && label.present? } || model.fetch("intercepts").size != width
            raise ArgumentError, "Invalid intercepts" unless model.fetch("intercepts").all? { |weight| weight.is_a?(Numeric) && weight.finite? }
            feature_count = @spaces.fetch(model.fetch("space")).fetch("idf").size
            format = model.fetch("weight_format", "dense")
            raise ArgumentError, "Unknown coefficient format" unless %w[dense sparse].include?(format)

            model["weights"] = model.fetch("weights").to_h do |key, weights|
              valid = weights.is_a?(Array) && if format == "sparse"
                weights.all? { |pair| pair.is_a?(Array) && pair.size == 2 && pair[0].is_a?(Integer) && (0...width).cover?(pair[0]) && pair[1].is_a?(Numeric) && pair[1].finite? }
                                              else
                weights.size == width && weights.all? { |weight| weight.is_a?(Numeric) && weight.finite? }
                                              end
              raise ArgumentError, "Invalid coefficients" unless valid

              index = Integer(key)
              raise ArgumentError, "Invalid feature index" unless (0...feature_count).cover?(index)

              [ index, weights ]
            end
            common = model.fetch("common_weights", {})
            raise ArgumentError, "Invalid shared coefficients" unless common.is_a?(Hash)

            model["common_weights"] = common.to_h do |key, weight|
              index = Integer(key)
              raise ArgumentError, "Invalid shared coefficient" unless (0...feature_count).cover?(index) && weight.is_a?(Numeric) && weight.finite?

              [ index, weight ]
            end
            raise ArgumentError, "Unknown activation" unless %w[softmax sigmoid_normalize margin].include?(model.fetch("activation"))
          else
            raise ArgumentError, "Invalid neighbor count" unless (1..25).cover?(model.fetch("k"))
          end
        end
      end
      @indices = {}
    end

    def candidates(card, category, attributes, prior: [])
      models = @models[category.name] or return []
      vectors = {}
      similarities = {}
      attributes.filter_map do |attribute|
        next if Reference::NAMING.include?(attribute.name)
        model = models[attribute.name] or next
        next if !model["replace_prior"] && prior.any? { |candidate| candidate.attribute == attribute.name }

        space = model.fetch("space")
        vector = vectors[space] ||= vectorize(card, @spaces.fetch(space))
        next if vector.empty?

        raw, score = if model["method"] == "knn"
          scores = similarities[space] ||= neighbor_scores(space, category.name, vector)
          nearest(model, @spaces.fetch(space), category.name, attribute.name, scores)
        else
          linear(model, vector)
        end
        next unless raw && score && score >= model.fetch("threshold")

        value = attribute.kind.normalize(raw, category: category) || (raw if attribute.kind.open?)
        next unless value.present?

        Candidate.new(attribute: attribute.name, value: value, raw: raw, source: "prior", rule: "context",
                      confidence: model.fetch("confidence", 0.5).clamp(0.01, 0.95), origin: "unverified_identity")
      end
    end

    private

    def probability?(value) = value.is_a?(Numeric) && value.finite? && value.between?(0, 1)

    def prepare_space(space)
      raise ArgumentError, "Invalid feature space" unless space.is_a?(Hash)

      features = space.fetch("features")
      idf = space.fetch("idf")
      raise ArgumentError, "Invalid feature vocabulary" unless features.is_a?(Array) && features.all? { |feature| feature.is_a?(String) } && idf.is_a?(Array) && features.uniq.size == features.size && features.size == idf.size
      raise ArgumentError, "Invalid feature weights" unless idf.all? { |weight| weight.is_a?(Numeric) && weight.finite? && weight.positive? }

      characters = space.fetch("description_chars")
      raise ArgumentError, "Invalid description limit" unless characters.is_a?(Integer) && (0..5000).cover?(characters)
      neighbors = space.fetch("neighbors", {})
      raise ArgumentError, "Invalid neighbors" unless neighbors.is_a?(Hash)

      neighbors.each_value do |rows|
        raise ArgumentError, "Invalid neighbor rows" unless rows.is_a?(Array)

        rows.each do |row|
          raise ArgumentError, "Invalid neighbor row" unless row.is_a?(Hash) && row["vector"].is_a?(Array)
          raise ArgumentError, "Invalid neighbor labels" unless row.fetch("values").is_a?(Hash) && row.fetch("values").values.all? { |value| value.is_a?(String) }
          raise ArgumentError, "Invalid neighbor vector" unless row.fetch("vector").all? do |pair|
            pair.is_a?(Array) && pair.size == 2 && pair[0].is_a?(Integer) && (0...idf.size).cover?(pair[0]) &&
              pair[1].is_a?(Numeric) && pair[1].finite? && pair[1] >= 0
          end
        end
      end
      space.merge("ids" => features.each_with_index.to_h)
    end

    def vectorize(card, space)
      counts = Hash.new(0)
      [ [ "t", card.heading, 3 ], [ "d", card.description.to_s[0, space.fetch("description_chars")], 1 ] ].each do |source, text, repeat|
        words = text.to_s.unicode_normalize(:nfkc).downcase.tr("ё", "е").scan(/[a-zа-я0-9]+/).first(300)
        names = words.map { |word| "#{source}:w:#{word}" } + words.each_cons(2).map { |a, b| "#{source}:b:#{a}/#{b}" }
        words.each do |word|
          token = "<#{word[0, 40]}>"
          [ 3, 4, 5 ].each { |size| [ token.length - size + 1, 0 ].max.times { |start| names << "#{source}:#{token[start, size]}" } }
        end
        names.each { |name| (index = space.fetch("ids")[name]) && counts[index] += repeat }
      end
      weights = counts.to_h { |index, count| [ index, count * space.fetch("idf")[index] ] }
      norm = Math.sqrt(weights.values.sum { |weight| weight * weight })
      norm.positive? ? weights.transform_values { |weight| weight / norm } : {}
    end

    def sigmoid(score)
      score >= 0 ? 1.0 / (1.0 + Math.exp(-score)) : Math.exp(score) / (1.0 + Math.exp(score))
    end

    def linear(model, vector)
      shared = model.fetch("common_weights", {})
      common_score = shared.empty? ? 0.0 : vector.sum { |feature, value| shared.fetch(feature, 0.0) * value }
      scores = model.fetch("intercepts").map { |value| value + common_score }
      vector.each do |feature, value|
        weights = model.fetch("weights")[feature] or next
        if model["weight_format"] == "sparse"
          weights.each { |index, weight| scores[index] += weight * value }
        else
          weights.each_index { |index| scores[index] += weights[index] * value }
        end
      end
      if model.fetch("activation") == "margin" && scores.size > 1
        best = scores.each_index.max_by { |index| [ scores[index], index ] }
        second = scores.each_index.reject { |index| index == best }.map { |index| scores[index] }.max
        return [ model.fetch("classes")[best], sigmoid(scores[best] - second) ]
      end
      probabilities = if model.fetch("activation") == "sigmoid_normalize"
        scores.map { |score| sigmoid(score) }
      else
        maximum = scores.max
        scores.map { |score| Math.exp(score - maximum) }
      end
      total = probabilities.sum
      return unless total.positive?

      best = probabilities.each_index.max_by { |index| [ probabilities[index], -index ] }
      [ model.fetch("classes")[best], probabilities[best] / total ]
    end

    def neighbor_scores(space_id, category, vector)
      index = (@indices[[ space_id, category ]] ||= begin
        rows = @spaces.fetch(space_id).fetch("neighbors", {}).fetch(category, [])
        rows.each_with_index.each_with_object({}) do |(row, number), found|
          row.fetch("vector").each { |feature, weight| (found[feature] ||= []) << [ number, weight ] }
        end
      end)
      vector.each_with_object(Hash.new(0.0)) do |(feature, weight), scores|
        index.fetch(feature, []).each { |number, other| scores[number] += weight * other }
      end
    end

    def nearest(model, space, category, attribute, scores)
      rows = space.fetch("neighbors", {}).fetch(category, [])
      eligible = scores.select { |number, score| score.positive? && rows[number].fetch("values")[attribute].present? }
      nearest = eligible.max_by(model.fetch("k")) { |number, score| [ score, number ] }.sort_by { |number, score| [ -score, -number ] }
      return if nearest.empty?

      votes = nearest.each_with_object(Hash.new(0.0)) { |(number, score), counts| counts[rows[number].fetch("values").fetch(attribute)] += score**3 }
      value, mass = votes.max_by { |label, weight| [ weight, label ] }
      [ value, nearest.first.last * mass / votes.values.sum ]
    end
  end
end
