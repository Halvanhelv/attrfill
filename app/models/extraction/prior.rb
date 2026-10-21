require "zlib"

module Extraction
  # What most cards of a category say (a kettle is electric, a pillow has no Wi-Fi): the last guess for an attribute
  # nothing else settled. Trusted as much as it was right on held-out cards of that category, measured per category.
  class Prior
    MIN_SHARE = 0.5

    def self.load(path)
      new(JSON.parse(Zlib.gunzip(path.binread))) if path.exist?
    end

    # PRIOR=off turns it off; by default the one bin/learn built, if any.
    def self.current
      return @current if defined?(@current)

      @current = ENV["PRIOR"] == "off" ? nil : load(Extraction.config_path("prior.json.gz"))
    end

    def self.reset!
      remove_instance_variable(:@current) if defined?(@current)
    end

    def self.build(rows, catalog)
      values = Hash.new { |hash, key| hash[key] = Hash.new(0) }
      rows.each do |row|
        category = catalog.detect(row.card).name
        row.labels.each { |attribute, value| values["#{category}/#{attribute}"][value] += 1 unless Reference::NAMING.include?(attribute) }
      end
      new(values.filter_map do |key, counted|
        value, seen = counted.max_by(&:last)
        [ key, value ] if seen > MIN_SHARE * counted.values.sum
      end.to_h)
    end

    def initialize(values)
      @values = values
    end

    def candidates(category, attributes)
      attributes.filter_map do |attribute|
        raw = @values["#{category.name}/#{attribute.name}"] or next
        value = attribute.kind.normalize(raw, category: category) || (raw if attribute.kind.open?) or next
        Candidate.build(attribute: attribute.name, value: value, raw: raw, source: "prior", rule: category.name)
      end
    end

    def save(path)
      path.dirname.mkpath
      path.binwrite(Zlib.gzip(JSON.generate(@values)))
    end
  end
end
