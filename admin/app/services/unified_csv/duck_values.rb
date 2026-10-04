# DuckDB's view of CSV values, as data-pipelines' unifier sees them: its
# read_csv guesses a type per column, and values then reach the output CSV
# through a ::VARCHAR cast (DuckDB formatting) and reach the matching and
# global IDs through JavaScript's toString of the node-api value. Checked
# against DuckDB v1.2.0. Dates and times are not detected (left as text).
module UnifiedCsv
  module DuckValues
    INT64 = (-(2**63))..(2**63 - 1)
    INTEGER = /\A\s*-?(?:0|[1-9]\d*)\s*\z/
    DECIMAL = /\A\s*-?(?:(?:0|[1-9]\d*)(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?\s*\z/
    BOOLEAN = /\A\s*(?:true|false|t|f)\s*\z/i

    # :boolean, :bigint, :double or :varchar for a column's values (nil is
    # an empty cell, which DuckDB reads as NULL).
    def self.sniff(values)
      present = values.compact
      return :varchar if present.empty?
      return :boolean if present.all? { |v| v.match?(BOOLEAN) }
      if present.all? { |v| v.match?(INTEGER) }
        return present.all? { |v| INT64.cover?(Integer(v.strip, 10)) } ? :bigint : :double
      end
      return :double if present.all? { |v| v.match?(DECIMAL) && v.strip.match?(/\d/) && !leading_zero?(v) }
      :varchar
    end

    def self.leading_zero?(value)
      value.strip.delete_prefix("-").match?(/\A0\d/)
    end

    # value::VARCHAR in DuckDB.
    def self.varchar(type, value)
      return nil if value.nil?
      case type
      when :bigint then Integer(value.strip, 10).to_s
      when :double then python_repr(Float(value.strip))
      when :boolean then boolean(value).to_s
      else value
      end
    end

    # String(value) in JavaScript for the value node-api returns.
    def self.js_string(type, value)
      return nil if value.nil?
      case type
      when :bigint then Integer(value.strip, 10).to_s
      when :double then js_number(Float(value.strip))
      when :boolean then boolean(value).to_s
      else value
      end
    end

    def self.boolean(value)
      value.strip.downcase.start_with?("t")
    end

    # [digits, exponent] of the shortest round-trip decimal (Ruby's
    # Float#to_s), such that |value| = d1.d2d3... x 10^exponent.
    def self.shortest(float)
      mantissa, exp = float.abs.to_s.split("e")
      int_part, frac = mantissa.split(".")
      digits = (int_part + frac.to_s).sub(/\A0+/, "")
      exponent = exp.to_i + int_part.length - 1 - (int_part + frac.to_s)[/\A0*/].length
      digits = digits.sub(/0+\z/, "")
      [ digits.empty? ? "0" : digits, digits.empty? ? 0 : exponent ]
    end

    # Python-style repr, which DuckDB's DOUBLE to VARCHAR follows: fixed
    # notation (with ".0" when whole) for exponents -4..15, else d.ddde±XX.
    def self.python_repr(float)
      sign = float.negative? || (float.zero? && 1.0 / float < 0) ? "-" : ""
      digits, exponent = shortest(float)
      if exponent.between?(-4, 15)
        sign + fixed(digits, exponent, whole_suffix: ".0")
      else
        mantissa = digits.length > 1 ? "#{digits[0]}.#{digits[1..]}" : digits
        format("%s%se%s%02d", sign, mantissa, exponent.negative? ? "-" : "+", exponent.abs)
      end
    end

    # Number.prototype.toString: fixed notation for exponents -6..20 (no
    # ".0" when whole), else d.ddde±X.
    def self.js_number(float)
      return "0" if float.zero?
      sign = float.negative? ? "-" : ""
      digits, exponent = shortest(float)
      if exponent.between?(-6, 20)
        sign + fixed(digits, exponent, whole_suffix: "")
      else
        mantissa = digits.length > 1 ? "#{digits[0]}.#{digits[1..]}" : digits
        "#{sign}#{mantissa}e#{exponent.negative? ? '-' : '+'}#{exponent.abs}"
      end
    end

    def self.fixed(digits, exponent, whole_suffix:)
      if exponent.negative?
        "0." + "0" * (-exponent - 1) + digits
      elsif digits.length > exponent + 1
        "#{digits[0..exponent]}.#{digits[(exponent + 1)..]}"
      else
        digits + "0" * (exponent + 1 - digits.length) + whole_suffix
      end
    end

    private_class_method :leading_zero?, :boolean, :shortest, :fixed
  end
end
