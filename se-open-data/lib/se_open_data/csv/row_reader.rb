module SeOpenData
  module CSV
    # This is an abstract base for classes that read a row of CSV data
    #
    # The idea is to extend this and curry the `headers` initializer
    # parameter with a hash defining the field mapping.
    #
    # The use of this is best illustrated by example. See the example
    # in {file:CSV_MAPPING.md}.
    class RowReader

      attr_reader :row, :headers

      # @param row [Hash{Symbol => String}] - Defines the field data, keyed by field ID
      # @param headers [Hash{Symbol => String}] - Defines the fields' header texts, keyed by field ID
      def initialize(row, headers)
        @row, @headers = row, headers
        @comments = []
      end

      # Gets a normalised postcode.
      #
      # @return [String] the postcode, uppercased, with whitespace removed.
      def postcode_normalized
        return "" unless postcode
        postcode.upcase.gsub(/\s+/, "")
      end

      # Implements the dynamic method mapping to field IDs.
      def method_missing(method, *args, &block)
        @headers.keys.include?(method) ?  @row[@headers[method]] : nil
      end

      # Appends a new comment to the list of comments for this row.
      #
      # @param comment [String] - the comment text to append.
      def add_comment(comment)
        @comments << comment
      end

      # 
      def row_with_comments
        new_row = ::CSV::Row.new(row.headers(), row.fields)
        new_row << @comments.join("\n")
      end
    end
  end
end

