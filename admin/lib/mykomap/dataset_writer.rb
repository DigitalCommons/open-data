require "json"
require "fileutils"

module Mykomap
  # Writes a dataset directory (items/, locations.json, searchable.json,
  # stub about.md) from an enumerable of item hashes. Ported from
  # apps/back-end/src/dataset.ts DatasetWriter.
  class DatasetWriter
    SEARCH_PROP = "searchString".freeze

    Stats = Struct.new(:counter, :written, :errors, keyword_init: true)

    attr_reader :prop_defs, :searched_props, :filtered_props, :languages

    # @param prop_defs - name -> PropDef hash
    # @param languages - config languages; the first is used to localise
    #   vocab labels in the search index (the TS code passes no language and
    #   relies on the vocab's first localisation; we pass the default
    #   language explicitly, which is the same thing for built configs)
    def initialize(prop_defs, languages)
      @prop_defs = prop_defs
      @languages = languages
      @searched_props = prop_defs.select { |_n, p| p.search? }.keys
      @filtered_props = prop_defs.select { |_n, p| p.filtered? }.keys
    end

    def round5(value)
      return nil if value.nil?
      (Coerce.numberify(value, nil)&.to_f&.round(5))
    end

    # Writes the dataset; dir_path must not pre-exist. Returns Stats.
    def write_dataset(dir_path, items)
      raise "Cannot create dataset with existing filesystem path: #{dir_path}" if File.exist?(dir_path)
      items_dir = File.join(dir_path, "items")
      FileUtils.mkdir_p(items_dir)

      stats = Stats.new(counter: 0, written: 0, errors: [])
      ids = Set.new
      searchable_prop_names = filtered_props + [ "id", SEARCH_PROP ]

      File.open(File.join(dir_path, "locations.json"), "w") do |locations|
        File.open(File.join(dir_path, "searchable.json"), "w") do |searchable|
          locations.write("[")
          searchable.write(%({   "itemProps":\n#{JSON.generate(searchable_prop_names)},\n    "values":[\n))

          items.each do |item|
            if ids.include?(item["id"])
              stats.errors << { "message" => "duplicate ID", "ix" => stats.counter, "id" => item["id"] }
              stats.counter += 1
              next
            end
            ids << item["id"]

            if stats.written != 0
              locations.write(",")
              searchable.write(",\n")
            end

            point = Coerce.to_point2d([ item["lng"], item["lat"] ], nil)
            if point
              point = point.map { |n| round5(n) }
              marker = marker_index(item)
              point << [ marker, 0 ].max.floor if marker
            end
            locations.write(JSON.generate(point))

            values = filtered_props.map { |name| item[name] }
            values << item["id"]
            values << text_index(item)
            searchable.write(JSON.generate(values))

            rounded = item.dup
            %w[lat lng].each { |k| rounded[k] = round5(rounded[k]) if rounded.key?(k) }
            File.write(File.join(items_dir, "#{stats.written}.json"), JSON.pretty_generate(rounded))

            stats.counter += 1
            stats.written += 1
          end

          locations.write("]")
          searchable.write("\n]}")
        end
      end

      about_path = File.join(dir_path, "about.md")
      File.write(about_path, "created on: #{Time.now}\n") unless File.exist?(about_path)

      stats
    end

    # Builds the normalised search string for an item.
    def text_index(item)
      searched_props.map do |name|
        prop_def = prop_defs[name]
        text = prop_def.text_for_value(item[name], languages.first)
        case text
        when String then TextSearch.normalise(text)
        when Array then text.map { |t| TextSearch.normalise(t) }.join(" ")
        else TextSearch.normalise(Coerce.stringify(text))
        end
      end.join(" ")
    end

    # Marker icon index for an item; nil means the default marker.
    # Overridden when the config defines customMarkers.
    def marker_index(_item)
      nil
    end
  end
end
