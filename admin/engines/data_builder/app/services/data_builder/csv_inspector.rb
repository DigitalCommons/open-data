require "csv"

module DataBuilder
  # CSV staging helpers: junk-stripping and column inspection, ported from
  # apps/back-end/src/dataset/inspect.ts.
  module CsvInspector
    MAX_DISTINCT = 500
    MAX_SAMPLES = 8
    NUMERIC_RX = /\A-?\d+(\.\d+)?\z/

    module_function

    # Strips a UTF-8 BOM and up to 5 junk lines above the real title row,
    # in place. A line is junk when fewer than half of the columns parsed
    # from that point are named. Returns the number of lines stripped.
    def strip_leading_junk(path)
      chunk = File.binread(path, 64 * 1024) || ""
      bom = chunk.start_with?("\xEF\xBB\xBF".b) ? 3 : 0

      offset = bom
      skipped = 0
      while skipped < 5
        nl = chunk.index("\n".b, offset)
        line_end = nl || chunk.length
        line = chunk[offset...line_end].to_s.force_encoding("UTF-8").scrub

        if line.strip.empty?
          break if nl.nil?
          offset = nl + 1
          skipped += 1
          next
        end

        names = begin
          row = CSV.parse_line(line.chomp("\r")) || []
          row.map { |c| c.to_s.strip }
        rescue CSV::MalformedCSVError
          break
        end
        break if names.count { |n| n != "" } * 2 > names.length

        break if nl.nil?
        offset = nl + 1
        skipped += 1
      end

      if offset > 0
        tmp = "#{path}.stripped"
        File.open(path, "rb") do |from|
          from.seek(offset)
          File.open(tmp, "wb") { |to| IO.copy_stream(from, to) }
        end
        File.rename(tmp, path)
      end
      skipped
    end

    # Inspects a CSV: headers, row count, sample rows and per-column stats.
    def inspect_csv(path, max_distinct: MAX_DISTINCT, max_samples: MAX_SAMPLES)
      headers = []
      sample_rows = []
      row_count = 0
      columns = []
      seen = []

      CSV.foreach(path, encoding: "bom|utf-8", liberal_parsing: true) do |row|
        row = row.map { |v| v.nil? ? "" : v.to_s }
        if headers.empty?
          headers = row
          columns = headers.map do |name|
            { "name" => name, "nonEmpty" => 0, "distinct" => [], "distinctTruncated" => false,
              "allNumeric" => true, "semicolons" => 0 }
          end
          seen = headers.map { Set.new }
          next
        end

        row_count += 1
        sample_rows << row if sample_rows.length < max_samples

        columns.each_with_index do |col, ix|
          value = row[ix]
          next if value.nil? || value == ""
          col["nonEmpty"] += 1
          col["semicolons"] += 1 if value.include?(";")
          col["allNumeric"] = false if col["allNumeric"] && !value.strip.match?(NUMERIC_RX)
          next if seen[ix].include?(value)
          if seen[ix].size >= max_distinct
            col["distinctTruncated"] = true
          else
            seen[ix] << value
            col["distinct"] << value
          end
        end
      end

      columns.each { |col| col["allNumeric"] = col["allNumeric"] && col["nonEmpty"] > 0 }
      { "headers" => headers, "rowCount" => row_count, "sampleRows" => sample_rows, "columns" => columns }
    end
  end
end
