require "csv"

module DataBuilder
  # Rewrites CSV vocab values into vocab term IDs per the builder's value
  # maps. Ported from apps/back-end/src/dataset/transform.ts.
  module CsvTransformer
    module_function

    # Headers of the config's multi-valued properties.
    def multi_value_headers(config)
      config["itemProps"].values
        .select { |spec| spec["type"] == "multi" && spec["from"] }
        .map { |spec| spec["from"] }
        .to_set
    end

    def map_value(map, value)
      return value if value == ""
      map[value] || map[value.strip] || value
    end

    # Applies value_maps to in_path, writing the transformed copy to
    # out_path. Unmapped values pass through unchanged (the build then fails
    # loudly rather than dropping them silently).
    def transform(in_path, out_path, value_maps, multi_headers)
      headers = nil
      File.open(out_path, "w") do |out|
        CSV.foreach(in_path, encoding: "bom|utf-8", liberal_parsing: true) do |row|
          row = row.map { |v| v.nil? ? "" : v.to_s }
          if headers.nil?
            headers = row
            out.write(CSV.generate_line(headers, row_sep: "\r\n"))
            next
          end
          mapped = row.each_with_index.map do |value, ix|
            map = value_maps[headers[ix]]
            next value if map.nil? || value == ""
            if multi_headers.include?(headers[ix])
              Mykomap::CsvParser.split_field(value).map { |v| map_value(map, v) }.join(";")
            else
              map_value(map, value)
            end
          end
          out.write(CSV.generate_line(mapped, row_sep: "\r\n"))
        end
      end
    end
  end
end
