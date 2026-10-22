require "zlib"

module Extraction
  # Values people confirmed or corrected for a product, keyed by its title: the next card with the same title gets them
  # as candidates. Colour words are left out of the key for every attribute but colour, as the colours of one product
  # share everything else. Built from reviews by ReviewLearning (config/confirmed.json.gz).
  class Confirmed
    # Confirmations that must agree, and none disagree, for a value to be trusted without review
    # (config/acceptance.yml, learning.confirmations).
    def self.trusted = Integer(Acceptance.policy.dig("learning", "confirmations") || 3)

    def self.load(path)
      new(JSON.parse(Zlib.gunzip(path.binread))) if path.exist?
    end

    # CONFIRMED=off turns it off.
    def self.current
      return @current if defined?(@current)

      @current = ENV["CONFIRMED"] == "off" ? nil : load(Extraction.config_path("confirmed.json.gz"))
    end

    def self.reset!
      remove_instance_variable(:@current) if defined?(@current)
    end

    def self.key(title, attribute)
      words = Text.key(title).split
      words = words.reject { |word| Dictionary["colors"].canonical(word) } unless attribute == "color"
      words.join(" ").presence
    end

    # [[title, attribute, value], ...] in.
    def self.build(records)
      table = Hash.new { |hash, key| hash[key] = Hash.new { |values, value| values[value] = 0 } }
      records.each do |title, attribute, value|
        key = Confirmed.key(title, attribute)
        table["#{attribute}|#{key}"][value] += 1 if key && value.present?
      end
      new(table)
    end

    def initialize(table)
      @table = table
    end

    def size = @table.size

    def save(path)
      path.dirname.mkpath
      path.binwrite(Zlib.gzip(JSON.generate(@table)))
    end

    # One candidate an attribute, when people agreed on a single value for this title; trusted after Confirmed.trusted.
    def candidates(card, attributes)
      attributes.filter_map do |attribute|
        key = Confirmed.key(card.heading, attribute.name) or next
        values = @table["#{attribute.name}|#{key}"]
        next unless values&.size == 1

        value, seen = values.first
        Candidate.build(attribute: attribute.name, value: value, raw: value, source: "confirmed",
                        rule: seen >= Confirmed.trusted ? "confirmed" : "confirmed_once")
      end
    end
  end
end
