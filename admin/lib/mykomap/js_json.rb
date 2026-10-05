require "json"

module Mykomap
  # JSON text with numbers as JavaScript's JSON.stringify writes them. The
  # json gem (2.10+) prints some floats with extra digits
  # (15.14093 -> 15.140930000000001), and Ruby writes whole floats as
  # "33.0" where JavaScript writes "33".
  module JsJson
    module_function

    def generate(value)
      JSON.generate(js(value))
    end

    def pretty_generate(value)
      JSON.pretty_generate(js(value))
    end

    def js(value)
      case value
      when Hash then value.transform_values { |v| js(v) }
      when Array then value.map { |v| js(v) }
      when Float then value.finite? ? JSON::Fragment.new(UnifiedCsv::DuckValues.js_number(value)) : nil
      else value
      end
    end
  end
end
