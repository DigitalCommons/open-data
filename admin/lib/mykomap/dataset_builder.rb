require "csv"

module Mykomap
  # Orchestrates building a dataset dir from a CSV + validated config.
  # Ported from apps/back-end/src/dataset/build.ts.
  module DatasetBuilder
    module_function

    # Constructs a DatasetWriter for a config, with custom marker support.
    # @param config - a Mykomap::Config.parse result
    def mk_dataset_writer(config, report = nil)
      factory = PropDefs::Factory.new(config["vocabs"], config["languages"])
      prop_defs = factory.mk_prop_defs(config["itemProps"])

      custom = config.dig("ui", "customMarkers")
      return DatasetWriter.new(prop_defs, config["languages"]) unless custom

      terms_to_icon = custom["termsToIconIndex"]
      highest = terms_to_icon.values.max
      if custom["markerIcons"].length - 1 < highest
        raise "config.ui.customMarkers.markerIcons doesn't have enough icons."
      end

      marker_name = custom["marker_property_name"]
      marker_prop = prop_defs[marker_name]
      raise "No item property called '#{marker_name}' found in the config definitions" if marker_prop.nil?
      raise "The item property '#{marker_name}' is not a vocab property" if marker_prop.uri.nil?
      ncname = marker_prop.uri.sub(/:\z/, "")
      raise "The marker property '#{marker_name}' does not reference a known vocab URI: #{marker_prop.uri}" unless config["vocabs"].key?(ncname)

      report&.call("Using the item property '#{marker_name}' to infer marker type")

      writer = DatasetWriter.new(prop_defs, config["languages"])
      writer.define_singleton_method(:marker_index) do |item|
        value = item[marker_name]
        next nil if value.nil?
        if marker_prop.type != "multi"
          # NB faithful to the TS `|| default` quirk: an icon index of 0 falls
          # back to the default, because 0 is falsy in JS
          ix = terms_to_icon[value]
          next((ix.nil? || ix == 0) ? terms_to_icon["default"] : ix)
        end
        Array(value).each do |v|
          return terms_to_icon[v] if terms_to_icon.key?(v)
        end
        terms_to_icon["default"]
      end
      writer
    end

    # Builds a dataset dir from a CSV file. Does not write config.json
    # (callers differ in how they want it written). Returns writer Stats.
    def build_dataset_from_csv(config, csv_path, out_path, report = nil)
      writer = mk_dataset_writer(config, report)
      rows = CSV.read(csv_path, encoding: "bom|utf-8", liberal_parsing: true)
      headers = (rows.shift || []).map(&:to_s)
      parser = CsvParser.row_parser(writer.prop_defs, headers)
      items = rows.lazy.map { |row| parser.call(row) }
      writer.write_dataset(out_path, items)
    end
  end
end
