module Extraction
  # Values a rule reads that labelled cards of the category showed to be mostly wrong: "LED" in a TV's description
  # names its backlight, not its panel; a monitor sold as 24" measures 23.8". When the cards agree on what such a
  # reading stands for, it is read as that; otherwise it is dropped, and what comes after the rules fills the attribute.
  # A value is judged both as read ("белый") and as written ("Starlight" read as "белый" is Apple's "сияющая звезда"):
  # the way it was written, being the narrower, is looked up first.
  # Learned by bin/learn from how often each value read by rule matched gold (config/unreliable.yml).
  class Unreliable
    MIN_READINGS = 20
    MAX_RATE = 0.3
    # Share of a value's readings whose gold is one other value, for the reading to stand for that value.
    MEANS_SHARE = 0.8
    SOURCES = %w[seller title description].freeze

    def self.load(path)
      new(YAML.load_file(path) || {}) if path.exist?
    end

    # UNRELIABLE=off turns it off; by default the one bin/learn built, if any.
    def self.current
      return @current if defined?(@current)

      @current = ENV["UNRELIABLE"] == "off" ? nil : load(Extraction.config_path("unreliable.yml"))
    end

    def self.reset!
      remove_instance_variable(:@current) if defined?(@current)
    end

    WRITTEN = "written:".freeze

    def self.key(category, attribute, source) = "#{category}/#{attribute}/#{source}"

    # What a value is counted and looked up as: the value read, and the way it was written.
    def self.forms(candidate) = [ "#{WRITTEN}#{candidate.raw.to_s.downcase.tr('ё', 'е').squish}", candidate.value.to_s ]

    # { key => { value => [readings, right, { gold => count }] } } in: the values right in too few of many readings,
    # each with the value its readings stand for when they agree on one.
    def self.build(counts)
      new(counts.each_with_object({}) do |(key, values), table|
        wrong = values.select { |_, (total, right, _)| total >= MIN_READINGS && right < MAX_RATE * total }
        next if wrong.empty?

        table[key] = wrong.to_h do |value, (total, _, golds)|
          gold, seen = golds.max_by(&:last)
          [ value, (gold if gold && gold != value.delete_prefix(WRITTEN) && seen >= MEANS_SHARE * total) ]
        end.sort.to_h
      end)
    end

    def initialize(table)
      @table = table.transform_values { |values| values.is_a?(Hash) ? values : values.to_h { |value| [ value, nil ] } }
    end

    def to_h = @table.sort.to_h

    def save(path) = path.write(to_h.to_yaml)

    # The reading as the category's cards show it should be read: unchanged, another value, or nil when dropped.
    def apply(category, candidate)
      return candidate unless SOURCES.include?(candidate.source)

      values = @table[Unreliable.key(category, candidate.attribute, candidate.source)] or return candidate
      form = Unreliable.forms(candidate).find { |name| values.key?(name) } or return candidate

      means = values[form]
      means && Candidate.build(attribute: candidate.attribute, value: means, raw: candidate.raw, source: candidate.source, rule: "unreliable",
                               origin: candidate.origin)
    end
  end
end
