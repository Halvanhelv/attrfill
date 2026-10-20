require "csv"

class Dataset
  # The predictions file: one line per card and attribute in CSV, one object per card in JSON.
  class Writer
    HEADERS = %w[id category attribute value confidence status source].freeze

    def self.open(path, spreadsheet_safe: false)
      writer = new(path, spreadsheet_safe: spreadsheet_safe)
      yield writer
    ensure
      writer&.close
    end

    def initialize(path, spreadsheet_safe: false)
      @json = Pathname(path).extname.casecmp?(".json")
      @spreadsheet_safe = spreadsheet_safe
      @io = File.open(path, "w")
      @first = true
      @io << (@json ? "[\n" : HEADERS.to_csv)
    end

    def <<(result)
      @json ? write_json(result) : write_csv(result)
      self
    end

    def close
      @io << "\n]\n" if @json
      @io.close
    end

    private

    def write_csv(result)
      result.findings.each do |finding|
        cells = [ result.card.id, result.category.name, finding.attribute, finding.value, finding.confidence,
                  finding.status, finding.source ]
        @io << cells.map { |cell| spreadsheet_cell(cell) }.to_csv
      end
    end

    # CSV quoting alone does not prevent spreadsheet formula interpretation.
    # Only browser downloads opt in; machine exports retain exact values.
    def spreadsheet_cell(value)
      if @spreadsheet_safe && value.is_a?(String) && value.match?(/\A[[:space:]\uFEFF]*[=+@\-\t\r\n]/)
        "'#{value}"
      else
        value
      end
    end

    def write_json(result)
      attributes = result.findings.to_h do |finding|
        [ finding.attribute, { value: finding.value, confidence: finding.confidence, status: finding.status,
                               source: finding.source } ]
      end

      @io << (@first ? "" : ",\n") << JSON.generate(id: result.card.id, category: result.category.name, attributes: attributes)
      @first = false
    end
  end
end
