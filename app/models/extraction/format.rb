module Extraction
  # How a number is written out: its unit and decimal mark. The catalog's `format` gives the default,
  # config/formats.yml what a labelled dataset was seen to use (`bin/learn`).
  module Format
    DEFAULT = { "suffix" => "", "decimal" => "." }.freeze
    NUMBER = /\A\s*(\d+(?:([.,])\d+)?)(.*?)\s*\z/m
    MIN_SEEN = 5
    UNIT_SUFFIX = /\A(?:[\p{L}\s"'′″”°%\/·∙.²³]|(?<=\p{L})[23])*\z/
    RANGE_WORDS = /#{Text::BEFORE}(?:от|до|более|менее|выше|ниже|свыше|over|under|above|below|more|less|to)#{Text::AFTER}/i

    module_function

    def of(attribute)
      saved = (learned[attribute.name] || {}).reject do |key, value|
        %w[suffix tb_suffix].include?(key) && !unit_suffix?(value)
      end
      DEFAULT.merge(attribute.options["format"] || {}).merge(saved)
    end

    def learned
      @learned ||= begin
        path = Extraction.config_path("formats.yml")
        path.exist? ? (YAML.load_file(path) || {}) : {}
      end
    end

    def reset! = @learned = nil

    def write(number, style) = "#{Text.trim(number).tr('.', style['decimal'])}#{style['suffix']}"

    # The style most gold values are written in, or nil when there are too few to tell.
    def detect(golds)
      parsed = golds.filter_map do |gold|
        match = gold.to_s.match(NUMBER)
        match if match && unit_suffix?(match[3])
      end
      return if parsed.size < MIN_SEEN

      terabytes, plain = parsed.partition { |match| match[3].match?(/\A\s*(тб|tb)\z/i) }
      style = { "suffix" => most(plain.map { |match| match[3] }) }
      style["decimal"] = most(parsed.filter_map { |match| match[2] }) if parsed.any? { |match| match[2] }
      style["tb_suffix"] = most(terabytes.map { |match| match[3] }) if terabytes.any?
      style.compact
    end

    def most(values) = values.tally.max_by(&:last)&.first

    # A learned suffix changes notation, never the numeric meaning. A range or
    # threshold such as "-5000 мАч" or '" и более' is not a unit.
    def unit_suffix?(suffix) = suffix.to_s.match?(UNIT_SUFFIX) && !suffix.to_s.match?(RANGE_WORDS)
  end
end
