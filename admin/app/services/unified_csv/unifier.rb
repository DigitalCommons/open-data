require "csv"

# Merges a project's cleaned tables into one row per organisation. A port
# of data-pipelines packages/data-unification (index, mergeItems and the
# unify SQL, exported by DuckDB), kept faithful so the output matches:
#
# - Each row is identified by "<code>/<Identifier>" (a scoped ID).
# - Rows sharing a value of a match_on column (';'-separated, per table's
#   match mapping) are merged, transitively, across and within tables.
# - A group's Identifier is its lowest scoped ID. From each table only the
#   row with the lowest Identifier in the group contributes.
# - Each field is the first non-empty value across tables in alphabetical
#   order. data-pipelines means to apply field_priorities first, but a bug
#   (DataUnifierConfig spreads `tables` where it means `fieldPriorities`)
#   leaves them empty; respect_field_priorities: true applies them.
# - Domains, Memberships and Identifiers combine all the group's rows.
# - Rows are ordered by Name ignoring case (unnamed last), then Identifier.
#
# Values pass through DuckDB's column types; see DuckValues.
module UnifiedCsv
  class Unifier
    PICKED_FIELDS = [
      [ "Name", :name ], [ "Description" ], [ "Website" ], [ "Primary Activity" ],
      [ "Organisational Structure" ], [ "Membership Type" ], [ "Country ID", :default, "UC Country ID" ],
      [ "Latitude", :default, "Source Latitude" ], [ "Longitude", :default, "Source Longitude" ],
      [ "Geo Container Latitude" ], [ "Geo Container Longitude" ], [ "Geo Container" ],
      [ "Geocoded Address" ], [ "Region" ]
    ].freeze

    Table = Struct.new(:code, :settings, :columns, :types, :rows, :rows_by_id, keyword_init: true)

    def initialize(settings, cleaned_paths, respect_field_priorities: false)
      @settings = settings
      @cleaned_paths = cleaned_paths
      @respect_field_priorities = respect_field_priorities
    end

    # Writes the unified CSV; returns counts of rows, groups and merged groups.
    def unify(output_path)
      tables = @settings.tables.map { |table| load_table(table) }
      groups = merge(tables)
      by_code = tables.index_by(&:code)
      alphabetical = tables.map(&:code).sort

      rows = groups.flat_map { |scoped_ids| output_rows(scoped_ids, by_code, alphabetical) }
      rows.sort_by!.with_index { |row, index| sort_key(row, index) }

      columns = output_columns(by_code, alphabetical)
      CSV.open(output_path, "w", quote_empty: false) do |csv|
        csv << columns
        rows.each { |row| csv << row.values_at(*columns) }
      end
      { rows: rows.size, groups: groups.size, merged: groups.count { |ids| ids.size > 1 } }
    end

    private

    def load_table(settings)
      csv = CSV.read(@cleaned_paths.fetch(settings.code), headers: true, encoding: "UTF-8")
      columns = csv.headers
      raw = csv.map { |row| row.fields.map { |value| value == "" ? nil : value } }
      types = columns.each_with_index.to_h { |column, index| [ column, DuckValues.sniff(raw.map { |r| r[index] }) ] }
      rows = raw.map { |values| columns.zip(values).to_h }
      table = Table.new(code: settings.code, settings: settings, columns: columns, types: types, rows: rows)
      table.rows_by_id = rows.group_by { |row| varchar(table, row, "Identifier") }.except(nil)
      table
    end

    def varchar(table, row, column)
      DuckValues.varchar(table.types.fetch(column, :varchar), row[column])
    end

    def js_string(table, row, column)
      DuckValues.js_string(table.types.fetch(column, :varchar), row[column])
    end

    # Groups of scoped IDs sharing match values (union-find).
    def merge(tables)
      parent = {}
      find = lambda do |id|
        root = id
        root = parent[root] until parent[root] == root
        id = parent[id].tap { parent[id] = root } until id == root
        root
      end
      by_value = Hash.new { |hash, key| hash[key] = [] }

      tables.each do |table|
        table.rows.each do |row|
          scoped_id = "#{table.code}/#{js_string(table, row, 'Identifier')}"
          parent[scoped_id] ||= scoped_id
          table.settings.match.each do |label, column|
            values = js_string(table, row, column)
            next if values.nil?
            values.split(";").each { |value| by_value[[ label, value ]] << scoped_id unless value == "" }
          end
        end
      end

      by_value.each_value do |ids|
        first = find.call(ids.first)
        ids.drop(1).each { |id| parent[find.call(id)] = first }
      end
      parent.keys.group_by { |id| find.call(id) }.values
    end

    def output_rows(scoped_ids, by_code, alphabetical)
      item_ids = scoped_ids.group_by { |id| id.split("/", 2).first }
        .transform_values { |ids| ids.map { |id| id.split("/", 2).last }.min }
      matches = alphabetical.to_h do |code|
        item_id = item_ids[code]
        [ code, item_id ? by_code[code].rows_by_id.fetch(item_id, []) : [] ]
      end

      # The SQL left-joins each table on Identifier, so duplicate
      # Identifiers within a table multiply the group's rows.
      combinations = matches.values.reject(&:empty?).then do |lists|
        lists.empty? ? [ [] ] : lists.first.product(*lists.drop(1))
      end
      present = matches.reject { |_, list| list.empty? }.keys
      global_id = scoped_ids.min

      combinations.map do |combination|
        joined = present.zip(combination).to_h
        build_row(global_id, joined, by_code, alphabetical)
      end
    end

    def build_row(global_id, joined, by_code, alphabetical)
      row = { "Identifier" => global_id }
      PICKED_FIELDS.each do |field, priority, alias_name|
        order = priority_order(priority || :default, alphabetical)
        source = order.find { |code| joined[code] && !joined[code][field].nil? }
        row[alias_name || field] = source && varchar(by_code[source], joined[source], field)
      end

      alphabetical.each do |code|
        by_code[code].settings.include_cols.each do |column|
          row["#{code}.#{column}"] = joined[code] && varchar(by_code[code], joined[code], column)
        end
      end

      domains = alphabetical.flat_map do |code|
        value = joined[code] && varchar(by_code[code], joined[code], "Domains")
        value.nil? ? [] : value.split(";", -1)
      end
      row["Domains"] = domains.uniq.sort.join(";")
      members = alphabetical.select { |code| joined[code] }
      row["Memberships"] = members.empty? ? nil : members.join(";").upcase
      row["Identifiers"] = members.empty? ? nil : members.map { |code| "#{code}=#{varchar(by_code[code], joined[code], 'Identifier')}" }.join(";")
      row["Country ID"] = row["UC Country ID"]&.downcase
      row["Latitude"] = row["Source Latitude"] || row["Geo Container Latitude"]
      row["Longitude"] = row["Source Longitude"] || row["Geo Container Longitude"]
      row
    end

    def priority_order(priority, alphabetical)
      return alphabetical unless @respect_field_priorities
      Array(@settings.field_priorities[priority.to_s]) + alphabetical
    end

    def sort_key(row, index)
      name = row["Name"]
      [ name.nil? ? 1 : 0, name.to_s.downcase, row["Identifier"].to_s, index ]
    end

    def output_columns(by_code, alphabetical)
      include_cols = alphabetical.flat_map { |code| by_code[code].settings.include_cols.map { |column| "#{code}.#{column}" } }
      [ "Identifier", *PICKED_FIELDS.map { |field, _, alias_name| alias_name || field }, *include_cols,
        "Domains", "Memberships", "Identifiers", "Country ID", "Latitude", "Longitude" ]
    end
  end
end
