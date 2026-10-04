# How a project's sources are cleaned and unified into one CSV, read from
# the project's `unify:` section in db/projects.yml. Mirrors the defs.ts of
# a data-pipelines app:
#
#   match_on:          unification columns, in order (propDefs)
#   field_priorities:  default/name table orders (fieldPriorities)
#   tables:            in order; code => settings, where
#     source:          data source directory
#     match:           match_on label => this table's column (props)
#     include_cols:    columns copied through as "<code>.<col>" (includeCols)
#     row_filter:      column => required value (rowFilter)
class UnifySettings
  Table = Data.define(:code, :source, :match, :include_cols, :row_filter)

  attr_reader :match_on, :field_priorities, :tables

  def self.from_definition(definition)
    tables = definition.fetch("tables").map do |code, info|
      Table.new(code: code, source: info.fetch("source"), match: info["match"] || {},
        include_cols: info["include_cols"] || [], row_filter: info["row_filter"] || {})
    end
    new(match_on: definition.fetch("match_on"), field_priorities: definition["field_priorities"] || {}, tables: tables)
  end

  def initialize(match_on:, field_priorities:, tables:)
    @match_on = match_on
    @field_priorities = field_priorities
    @tables = tables
    tables.each do |table|
      unknown = table.match.keys - match_on
      raise ArgumentError, "#{table.code} matches on #{unknown.join(', ')}, not in match_on" if unknown.any?
    end
  end

  def table(code)
    tables.find { |table| table.code == code }
  end
end
