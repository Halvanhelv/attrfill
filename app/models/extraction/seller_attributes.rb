module Extraction
  # Sellers hand attributes over as JSON, as a Python dict, or as "key: value" lines.
  module SellerAttributes
    PAIR = /\A\s*([^:=]{1,80}?)\s*[:=]\s*(.+?)\s*\z/

    module_function

    def parse(raw)
      pairs =
        case raw
        when Hash then raw
        when Array then from_list(raw)
        when nil then {}
        else from_string(raw.to_s)
        end

      pairs.each_with_object({}) do |(key, value), result|
        value = value.is_a?(Array) ? value.join(", ") : value
        result[Text.key(key)] = Text.clean(value) if key.present? && value.to_s.strip.present?
      end
    end

    def from_string(string)
      return {} if string.blank?

      parsed = json(string) || json(string.gsub(/(?<=[{,\[:\s])'|'(?=[}\],:\s])/, '"'))
      return parse(parsed) if parsed

      string.split(/[;\n|]+/).filter_map { |part| part.match(PAIR)&.captures }.to_h
    end

    def from_list(list)
      list.filter_map do |item|
        next item.first(2) if item.is_a?(Array)
        next unless item.is_a?(Hash)

        item = item.transform_keys(&:to_s)
        key = item["name"] || item["key"] || item["attribute"] || item["title"]
        key ? [ key, item["value"] ] : item.first
      end.to_h
    end

    def json(string)
      parsed = JSON.parse(string)
      parsed if parsed.is_a?(Hash) || parsed.is_a?(Array)
    rescue JSON::ParserError
      nil
    end
  end
end
