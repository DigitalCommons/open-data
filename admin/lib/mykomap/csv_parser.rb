module Mykomap
  # Parses CSV rows into dataset item hashes per the prop definitions.
  # Ported from apps/back-end/src/dataset/csv.ts.
  module CsvParser
    class ValidationError < StandardError; end

    MULTI_OPTS = { delim: ";", escape: "\\" }.freeze

    module_function

    def empty?(value)
      value.nil? || value == ""
    end

    # Splits on a delimiter honouring an escape char; port of splitField.
    def split_field(field, delim: ";", escape: "\\")
      subfields = []
      buffer = +""
      escaped = false
      field.each_char do |ch|
        if escaped
          buffer << ch
          escaped = false
        elsif ch == delim
          subfields << buffer
          buffer = +""
        elsif ch == escape
          escaped = true
        else
          buffer << ch
        end
      end
      subfields << buffer
    end

    def parse_value(spec_or_def, value)
      as = spec_or_def.respond_to?(:as) ? spec_or_def.as : spec_or_def["as"]
      nullable = spec_or_def.respond_to?(:nullable) ? spec_or_def.nullable : spec_or_def["nullable"] == true
      strict = spec_or_def.respond_to?(:strict) ? spec_or_def.strict : spec_or_def["strict"] == true

      if nullable
        if strict
          case as
          when "string" then empty?(value) ? value : strict_string(value)
          when "number" then empty?(value) ? nil : strict_number(value)
          when "boolean" then empty?(value) ? nil : strict_bool(value)
          else value
          end
        else
          case as
          when "string" then value == "" ? value : Coerce.stringify(value, nil)
          when "number" then empty?(value) ? nil : Coerce.numberify(value, nil)
          when "boolean" then empty?(value) ? nil : Coerce.boolify(value, nil)
          else value
          end
        end
      elsif strict
        case as
        when "string" then strict_string(value)
        when "number" then strict_number(value)
        when "boolean" then strict_bool(value)
        else value
        end
      else
        case as
        when "string" then Coerce.stringify(value, "")
        when "number" then Coerce.numberify(value, 0)
        when "boolean" then Coerce.boolify(value, false)
        else value
        end
      end
    end

    def strict_string(value)
      raise ValidationError, "expected a string, got #{value.inspect}" unless value.is_a?(String)
      value
    end

    def strict_number(value)
      raise ValidationError, "expected a number, got #{value.inspect}" unless value.is_a?(Numeric)
      value
    end

    def strict_bool(value)
      raise ValidationError, "expected a boolean, got #{value.inspect}" unless value == true || value == false
      value
    end

    def parse_vocab(prop_def, value)
      case value
      when String
        terms = prop_def.i18n_vocab.values.first&.fetch("terms", {}) || {}
        return value if terms.key?(value)
        return nil if value == ""
        raise ValidationError, "Invalid #{prop_def.uri} vocab URI: '#{value}'"
      when nil
        nil
      else
        raise ValidationError, "Invalid #{prop_def.uri} vocab URI: '#{value}'"
      end
    end

    def parse_multi(prop_def, value)
      case value
      when String
        values = split_field(value, **MULTI_OPTS).reject { |v| v == "" }
        case prop_def.of.type
        when "value" then values.map { |v| parse_value(prop_def.of, v) }
        when "vocab" then values.map { |v| parse_vocab(prop_def.of, v) }
        end
      when nil
        []
      else
        raise ValidationError, "Invalid multi-value property: '#{value}'"
      end
    end

    def parse_prop(prop_def, value)
      case prop_def.type
      when "value" then parse_value(prop_def, value)
      when "vocab" then parse_vocab(prop_def, value)
      when "multi" then parse_multi(prop_def, value)
      end
    end

    # Returns a lambda(row) -> item Hash, bound to the CSV headers.
    # Raises ValidationError when expected headers are missing.
    def row_parser(prop_defs, headers)
      id_prop = prop_defs["id"] or raise ValidationError, "PropDefs must have the mandatory id property defined"
      raise ValidationError, "The PropDef for \"id\" must define a 'from' property" if id_prop.from.nil?

      missing = []
      bound = prop_defs.map do |name, prop_def|
        ix = prop_def.from ? headers.index(prop_def.from) : nil
        missing << prop_def.from if prop_def.from && ix.nil?
        [ name, prop_def, ix ]
      end
      raise ValidationError, "CSV has missing headers. Expected: #{missing.inspect}" if missing.any?

      lambda do |row|
        bound.each_with_object({}) do |(name, prop_def, ix), item|
          # CSV parsers give nil for empty/missing cells; udsv gives "".
          value = ix ? (row[ix].nil? ? "" : row[ix]) : nil
          begin
            item[name] = parse_prop(prop_def, value)
          rescue ValidationError => e
            raise ValidationError,
              "whilst parsing prop '#{name}' from CSV field ##{ix ? ix + 1 : '?'}, '#{prop_def.from}': #{e.message}"
          end
        end
      end
    end
  end
end
