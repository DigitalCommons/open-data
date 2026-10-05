module Mykomap
  # Value coercions ported from libs/common/src/utils.ts.
  module Coerce
    module_function

    def text_to_bool(text)
      case text.strip.downcase
      when "true", "t", "yes", "y", "1" then true
      when "false", "f", "no", "n", "0" then false
      end
    end

    def stringify(value, default = "")
      value.is_a?(String) ? value : default
    end

    def numberify(value, default = 0)
      case value
      when Numeric then value.to_f.nan? ? default : value
      when String
        n = Float(value.slice(/\A\s*-?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/) || "", exception: false)
        n.nil? ? default : n
      else default
      end
    end

    def boolify(value, default = false)
      case value
      when nil then default
      when String then text_to_bool(value).nil? ? default : text_to_bool(value)
      when Numeric then value.zero?
      when true, false then value
      else default
      end
    end

    # Converts to a [x, y] pair of numbers, or default. Port of toPoint2d.
    def to_point2d(value, default = nil)
      return default unless value.is_a?(Array)
      return default if value.length < 2
      if value.length == 2 && value[0].is_a?(Numeric) && value[1].is_a?(Numeric)
        return default if value[0].to_f.nan? || value[1].to_f.nan?
        return value
      end
      p0 = numberify(value[0], nil)
      p1 = numberify(value[1], nil)
      return [ p0, p1 ] if p0.is_a?(Numeric) && p1.is_a?(Numeric)
      default
    end
  end
end
