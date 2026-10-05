require "time"

module Mykomap
  # Validates and normalises a MykoMap dataset config, ported from the zod
  # ConfigData schema (libs/common/src/api/contract.ts). Like zod:
  # - unknown object keys are stripped
  # - defaults are materialised (popup item styles, leftPaneWidth etc.)
  # Raises Config::Invalid, whose message lists the issues zod-style.
  module Config
    class Invalid < StandardError
      attr_reader :issues

      def initialize(issues)
        @issues = issues
        listed = issues.first(20).map { |path, msg| " - #{path.empty? ? '(root)' : path}: #{msg}" }
        listed << " - ... and #{issues.size - 20} more" if issues.size > 20
        super("invalid dataset config:\n#{listed.join("\n")}")
      end
    end

    PROP_TYPES = %w[value vocab multi].freeze
    VALUE_AS = %w[string boolean number].freeze
    VALUE_STYLES = %w[text address hyperlink].freeze

    module_function

    # Parses and normalises a config Hash (string or symbol keys). Returns a
    # new string-keyed Hash. Raises Invalid when validation fails.
    def parse(raw)
      state = { issues: [] }
      raw = deep_stringify(raw)
      unless raw.is_a?(Hash)
        raise Invalid, [ [ "", "expected an object" ] ]
      end

      out = {}
      out["prefixes"] = parse_prefixes(raw["prefixes"], "prefixes", state)
      out["vocabs"] = parse_vocabs(raw["vocabs"], "vocabs", state)
      out["itemProps"] = parse_item_props(raw["itemProps"], "itemProps", state)
      out["languages"] = parse_languages(raw["languages"], "languages", state)
      if raw.key?("submaps")
        out["submaps"] = parse_submaps(raw["submaps"], "submaps", state)
      end
      out["ui"] = parse_ui(raw["ui"], "ui", state)
      out["popup"] = parse_popup(raw["popup"], "popup", state)

      raise Invalid, state[:issues] if state[:issues].any?
      out
    end

    def deep_stringify(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
      when Array then value.map { |v| deep_stringify(v) }
      else value
      end
    end

    def issue(state, path, message)
      state[:issues] << [ path, message ]
      nil
    end

    def expect_hash(value, path, state)
      return value if value.is_a?(Hash)
      issue(state, path, "expected an object")
    end

    def expect_string(value, path, state, optional: false)
      return nil if optional && value.nil?
      return value if value.is_a?(String)
      issue(state, path, "expected a string")
    end

    def expect_number(value, path, state, optional: false)
      return nil if optional && value.nil?
      return value if value.is_a?(Numeric)
      issue(state, path, "expected a number")
    end

    def expect_bool(value, path, state, optional: false)
      return nil if optional && value.nil?
      return value if value == true || value == false
      issue(state, path, "expected a boolean")
    end

    def parse_prefixes(value, path, state)
      hash = expect_hash(value, path, state) or return {}
      hash.each do |uri, ncname|
        issue(state, "#{path}.#{uri}", "Invalid prefix URI format") unless uri.is_a?(String) && uri.match?(Rx::PREFIX_URI)
        issue(state, "#{path}.#{uri}", "Invalid NCName format") unless ncname.is_a?(String) && ncname.match?(Rx::NCNAME)
      end
      hash
    end

    def parse_vocabs(value, path, state)
      hash = expect_hash(value, path, state) or return {}
      hash.each do |vocab_id, i18n|
        vpath = "#{path}.#{vocab_id}"
        issue(state, vpath, "Invalid NCName format") unless vocab_id.match?(Rx::NCNAME)
        i18n = expect_hash(i18n, vpath, state) or next
        i18n.each do |lang, vocab|
          lpath = "#{vpath}.#{lang}"
          issue(state, lpath, "invalid language code") unless Rx::ISO639_1_CODES.include?(lang)
          vocab = expect_hash(vocab, lpath, state) or next
          expect_string(vocab["title"], "#{lpath}.title", state)
          terms = expect_hash(vocab["terms"], "#{lpath}.terms", state) or next
          terms.each do |term, label|
            issue(state, "#{lpath}.terms.#{term}", "Invalid NCName format") unless term.match?(Rx::NCNAME)
            issue(state, "#{lpath}.terms.#{term}", "expected a string") unless label.is_a?(String)
          end
          vocab.slice!("title", "terms")
        end
      end
      hash
    end

    def parse_prop(value, path, state, inner: false)
      hash = expect_hash(value, path, state) or return nil
      out = {}
      type = hash["type"]
      unless PROP_TYPES.include?(type)
        issue(state, "#{path}.type", "invalid property type")
        return nil
      end
      out["type"] = type

      unless inner
        out["from"] = expect_string(hash["from"], "#{path}.from", state, optional: true) if hash.key?("from")
        if hash.key?("titleUri")
          title_uri = expect_string(hash["titleUri"], "#{path}.titleUri", state, optional: true)
          if title_uri && !title_uri.match?(Rx::QNAME)
            issue(state, "#{path}.titleUri", "Invalid QName format")
          end
          out["titleUri"] = title_uri
        end
        if hash.key?("filter")
          filter = hash["filter"]
          if filter == true || filter == false
            out["filter"] = filter
          elsif filter.is_a?(Hash) && filter["preset"] == true
            out["filter"] = { "preset" => true, "to" => filter["to"] }
          else
            issue(state, "#{path}.filter", "expected a boolean or {preset: true, to: ...}")
          end
        end
        out["search"] = expect_bool(hash["search"], "#{path}.search", state, optional: true) if hash.key?("search")
      end

      case type
      when "value"
        if hash.key?("as")
          issue(state, "#{path}.as", "invalid 'as' value") unless VALUE_AS.include?(hash["as"])
          out["as"] = hash["as"]
        end
        out["strict"] = expect_bool(hash["strict"], "#{path}.strict", state, optional: true) if hash.key?("strict")
        out["nullable"] = expect_bool(hash["nullable"], "#{path}.nullable", state, optional: true) if hash.key?("nullable")
      when "vocab"
        uri = expect_string(hash["uri"], "#{path}.uri", state)
        issue(state, "#{path}.uri", "Invalid abbreviated URI format") if uri && !uri.match?(Rx::ABBREV_URI)
        out["uri"] = uri
        if hash.key?("sorted")
          sorted = hash["sorted"]
          unless sorted == true || sorted == false || %w[asc desc].include?(sorted)
            issue(state, "#{path}.sorted", "expected a boolean, 'asc' or 'desc'")
          end
          out["sorted"] = sorted
        end
      when "multi"
        out["of"] = parse_prop(hash["of"], "#{path}.of", state, inner: true)
        if out["of"] && out["of"]["type"] == "multi"
          issue(state, "#{path}.of", "multi properties cannot nest")
        end
      end
      out.compact
    end

    def parse_item_props(value, path, state)
      hash = expect_hash(value, path, state) or return {}
      out = {}
      id_prop = hash["id"]
      if id_prop.nil?
        issue(state, "#{path}.id", "the 'id' itemProp is required")
      end
      hash.each do |name, spec|
        prop = parse_prop(spec, "#{path}.#{name}", state)
        next if prop.nil?
        if name == "id"
          issue(state, "#{path}.id.type", "id must be a value property") unless prop["type"] == "value"
          issue(state, "#{path}.id.filter", "id may not be filterable") if prop["filter"] && prop["filter"] != false
        end
        out[name] = prop
      end
      out
    end

    def parse_languages(value, path, state)
      unless value.is_a?(Array) && value.any?
        issue(state, path, "expected a non-empty array of language codes")
        return []
      end
      value.each_with_index do |lang, ix|
        issue(state, "#{path}.#{ix}", "invalid language code") unless Rx::ISO639_1_CODES.include?(lang)
      end
      value
    end

    def parse_map_bounds(value, path, state)
      ok = value.is_a?(Array) && value.length == 2 &&
        value.all? { |p| p.is_a?(Array) && p.length == 2 && p.all? { |n| n.is_a?(Numeric) } }
      return value if ok
      issue(state, path, "expected [[w, s], [e, n]] numeric bounds")
    end

    def parse_submaps(value, path, state)
      hash = expect_hash(value, path, state) or return {}
      out = {}
      hash.each do |key, submap|
        spath = "#{path}.#{key}"
        submap = expect_hash(submap, spath, state) or next
        entry = {}
        locked = submap["lockedFilter"]
        if locked.is_a?(Array) && locked.any?
          locked.each_with_index do |qname, ix|
            unless qname.is_a?(String) && qname.match?(Rx::QNAME)
              issue(state, "#{spath}.lockedFilter.#{ix}", "Invalid QName format")
            end
          end
          entry["lockedFilter"] = locked
        else
          issue(state, "#{spath}.lockedFilter", "expected a non-empty array of QNames")
        end
        entry["mapBounds"] = parse_map_bounds(submap["mapBounds"], "#{spath}.mapBounds", state) if submap.key?("mapBounds")
        entry["aboutPrefix"] = expect_string(submap["aboutPrefix"], "#{spath}.aboutPrefix", state, optional: true) if submap.key?("aboutPrefix")
        entry["title"] = expect_string(submap["title"], "#{spath}.title", state, optional: true) if submap.key?("title")
        out[key] = entry.compact
      end
      out
    end

    def parse_ui(value, path, state)
      hash = expect_hash(value, path, state) or return {}
      out = {}
      out["directory_panel_field"] = expect_string(hash["directory_panel_field"], "#{path}.directory_panel_field", state)
      out["title"] = expect_string(hash["title"], "#{path}.title", state, optional: true) if hash.key?("title")
      if hash.key?("dataLastUpdated")
        updated = expect_string(hash["dataLastUpdated"], "#{path}.dataLastUpdated", state, optional: true)
        if updated
          begin
            Time.iso8601(updated)
          rescue ArgumentError
            issue(state, "#{path}.dataLastUpdated", "invalid ISO datetime")
          end
          out["dataLastUpdated"] = updated
        end
      end
      out["show_map_key"] = expect_bool(hash["show_map_key"], "#{path}.show_map_key", state, optional: true) if hash.key?("show_map_key")

      if hash.key?("customMarkers")
        cm = expect_hash(hash["customMarkers"], "#{path}.customMarkers", state)
        if cm
          marker = {}
          marker["marker_property_name"] = expect_string(cm["marker_property_name"], "#{path}.customMarkers.marker_property_name", state)
          icons = cm["markerIcons"]
          if icons.is_a?(Array) && icons.all? { |i| i.is_a?(String) }
            marker["markerIcons"] = icons
          else
            issue(state, "#{path}.customMarkers.markerIcons", "expected an array of strings")
          end
          tti = expect_hash(cm["termsToIconIndex"], "#{path}.customMarkers.termsToIconIndex", state)
          if tti
            issue(state, "#{path}.customMarkers.termsToIconIndex.default", "expected a number") unless tti["default"].is_a?(Numeric)
            tti.each do |term, ix|
              issue(state, "#{path}.customMarkers.termsToIconIndex.#{term}", "expected a number") unless ix.is_a?(Numeric)
            end
            marker["termsToIconIndex"] = tti
          end
          out["customMarkers"] = marker.compact
        end
      end

      if hash.key?("map")
        map = expect_hash(hash["map"], "#{path}.map", state)
        if map
          entry = {}
          entry["mapBounds"] = parse_map_bounds(map["mapBounds"], "#{path}.map.mapBounds", state) if map.key?("mapBounds")
          out["map"] = entry.compact
        end
      end

      if hash.key?("logo")
        logo = expect_hash(hash["logo"], "#{path}.logo", state)
        if logo
          entry = {}
          %w[largeLogo smallLogo altText].each do |key|
            entry[key] = expect_string(logo[key], "#{path}.logo.#{key}", state, optional: true) if logo.key?(key)
          end
          { "smallScreenPosition" => %w[top left], "largeScreenPosition" => %w[bottom right] }.each do |key, fields|
            next unless logo.key?(key)
            pos = expect_hash(logo[key], "#{path}.logo.#{key}", state)
            next unless pos
            entry[key] = fields.each_with_object({}) do |f, h|
              h[f] = expect_string(pos[f], "#{path}.logo.#{key}.#{f}", state, optional: true) if pos.key?(f)
            end.compact
          end
          out["logo"] = entry.compact
        end
      end
      out.compact
    end

    def parse_popup_item(value, path, state)
      hash = expect_hash(value, path, state) or return nil
      out = {}
      out["itemProp"] = expect_string(hash["itemProp"], "#{path}.itemProp", state)
      style = hash.fetch("valueStyle", "text")
      issue(state, "#{path}.valueStyle", "invalid valueStyle") unless VALUE_STYLES.include?(style)
      out["valueStyle"] = style
      out["showBullets"] = hash.key?("showBullets") ? expect_bool(hash["showBullets"], "#{path}.showBullets", state) : false
      out["singleColumnLimit"] = expect_number(hash["singleColumnLimit"], "#{path}.singleColumnLimit", state, optional: true) if hash.key?("singleColumnLimit")
      out["showLabel"] = hash.key?("showLabel") ? expect_bool(hash["showLabel"], "#{path}.showLabel", state) : false
      out["hyperlinkBaseUri"] = hash.key?("hyperlinkBaseUri") ? expect_string(hash["hyperlinkBaseUri"], "#{path}.hyperlinkBaseUri", state) : ""
      out["displayText"] = expect_string(hash["displayText"], "#{path}.displayText", state, optional: true) if hash.key?("displayText")
      out["analyticOnClick"] = hash.key?("analyticOnClick") ? expect_bool(hash["analyticOnClick"], "#{path}.analyticOnClick", state) : false
      out["showBullets"] = false if out["showBullets"].nil?
      out["showLabel"] = false if out["showLabel"].nil?
      out["analyticOnClick"] = false if out["analyticOnClick"].nil?
      out["hyperlinkBaseUri"] = "" if out["hyperlinkBaseUri"].nil?
      out.compact
    end

    def parse_popup(value, path, state)
      hash = expect_hash(value, path, state) or return {}
      out = {}
      out["titleProp"] = expect_string(hash["titleProp"], "#{path}.titleProp", state)
      width = hash.fetch("leftPaneWidth", "70%")
      out["leftPaneWidth"] = expect_string(width, "#{path}.leftPaneWidth", state) || "70%"
      %w[leftPane topRightPane bottomRightPane].each do |pane|
        items = hash[pane]
        unless items.is_a?(Array)
          issue(state, "#{path}.#{pane}", "expected an array")
          out[pane] = []
          next
        end
        out[pane] = items.each_with_index.map { |item, ix| parse_popup_item(item, "#{path}.#{pane}.#{ix}", state) }.compact
      end
      out.compact
    end
  end
end
