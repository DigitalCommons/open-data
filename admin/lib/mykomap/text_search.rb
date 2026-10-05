module Mykomap
  # Port of libs/common/src/text-search.ts TextSearch.normalise.
  module TextSearch
    # Normalises text into an indexable form. NOTE: like the original, only
    # the FIRST ' or ` is dropped (the JS regex lacks the /g flag) - keep the
    # quirk so indexes and searches stay consistent with the monolith.
    def self.normalise(text)
      text.downcase
        .sub(/['`]/, "")
        .gsub(/[^\w ]+/, " ")
        .gsub(/\s+/, " ")
        .strip
    end
  end
end
