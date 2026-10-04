# JavaScript string semantics the data-pipelines port has to reproduce.
module UnifiedCsv
  module Js
    # String.prototype.trim: ECMAScript WhiteSpace and LineTerminator, which
    # unlike Ruby's strip include no-break and other Unicode spaces.
    WHITESPACE = "[\t\n\v\f\r    -     　﻿]"
    TRIM = /\A#{WHITESPACE}+|#{WHITESPACE}+\z/

    def self.trim(value)
      value.gsub(TRIM, "")
    end
  end
end
