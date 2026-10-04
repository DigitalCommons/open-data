require "test_helper"
require "csv"

# Expected behaviour is data-pipelines' packages/data-unification
# (index, mergeItems, unify SQL and DuckDB's CSV export).
class UnifiedCsv::UnifierTest < ActiveSupport::TestCase
  STANDARD = "Identifier,Name,Description,Website,Primary Activity,Organisational Structure,Membership Type," \
             "Country ID,Latitude,Longitude,Geo Container,Geo Container Latitude,Geo Container Longitude," \
             "Geocoded Address,Region,Domains,CUK ID,Dataset"

  setup { @dir = Pathname.new(Dir.mktmpdir("unifier-test")) }
  teardown { FileUtils.remove_entry(@dir) }

  # rows: hashes of standard column => value
  def table(code, rows)
    path = @dir + "#{code}.cleaned.csv"
    columns = STANDARD.split(",")
    CSV.open(path, "w", quote_empty: false) do |csv|
      csv << columns
      rows.each { |row| csv << columns.map { |column| column == "Dataset" ? code : row[column] } }
    end
    [ code, path ]
  end

  def settings(tables, match_on: [ "Domains", "CUK ID" ], priorities: {})
    UnifySettings.from_definition("match_on" => match_on, "field_priorities" => priorities, "tables" => tables)
  end

  def unify(settings, cleaned, **options)
    output = @dir + "unified.csv"
    stats = UnifiedCsv::Unifier.new(settings, cleaned.to_h, **options).unify(output)
    [ CSV.read(output, headers: true).map(&:to_h), stats, File.read(output) ]
  end

  DOMAINS = { "Domains" => "Domains" }.freeze

  test "merges rows sharing a domain, transitively and across tables" do
    s = settings({ "ica" => { "source" => "i", "match" => DOMAINS }, "dc" => { "source" => "d", "match" => DOMAINS },
                   "cmc" => { "source" => "c", "match" => DOMAINS } })
    cleaned = [
      table("ica", [ { "Identifier" => "I1", "Name" => "Ica One", "Domains" => "a.coop" } ]),
      table("dc", [ { "Identifier" => "d9", "Name" => "Dc One", "Domains" => "a.coop;b.coop" },
                    { "Identifier" => "d2", "Name" => "Other", "Domains" => "z.coop" } ]),
      table("cmc", [ { "Identifier" => "5", "Name" => "Cmc One", "Domains" => "b.coop;c.coop" } ])
    ]
    rows, stats = unify(s, cleaned)

    assert_equal 2, rows.size
    merged = rows.find { |row| row["Identifier"] == "cmc/5" }
    assert_equal "CMC;DC;ICA", merged["Memberships"]
    assert_equal "cmc=5;dc=d9;ica=I1", merged["Identifiers"]
    assert_equal "a.coop;b.coop;c.coop", merged["Domains"]
    assert_equal({ rows: 2, groups: 2, merged: 1 }, stats)
  end

  test "only configured match columns link rows" do
    s = settings({ "ica" => { "source" => "i", "match" => DOMAINS }, "fca" => { "source" => "f" } })
    cleaned = [ table("ica", [ { "Identifier" => "1", "Name" => "A", "Domains" => "a.coop" } ]),
                table("fca", [ { "Identifier" => "2", "Name" => "B", "Domains" => "a.coop" } ]) ]
    rows, = unify(s, cleaned)
    assert_equal [ "ica/1", "fca/2" ], rows.map { |row| row["Identifier"] }
  end

  test "Co-ops UK identifiers link to other sources' CUK ID" do
    s = settings({ "cuk" => { "source" => "c", "match" => { "Domains" => "Domains", "CUK ID" => "Identifier" } },
                   "wc" => { "source" => "w", "match" => { "Domains" => "Domains", "CUK ID" => "CUK ID" } } })
    cleaned = [ table("cuk", [ { "Identifier" => "1234", "Name" => "Coop" } ]),
                table("wc", [ { "Identifier" => "w1", "Name" => "Coop", "CUK ID" => "1234" } ]) ]
    rows, = unify(s, cleaned)
    assert_equal [ "cuk/1234" ], rows.map { |row| row["Identifier"] }
    assert_equal "CUK;WC", rows.first["Memberships"]
  end

  test "takes each field from the first table alphabetically, ignoring priorities as data-pipelines does" do
    tables = { "ica" => { "source" => "i", "match" => DOMAINS }, "acmei" => { "source" => "a", "match" => DOMAINS } }
    cleaned = [ table("ica", [ { "Identifier" => "1", "Name" => "Ica Name", "Description" => "ica desc", "Domains" => "a.coop" } ]),
                table("acmei", [ { "Identifier" => "2", "Name" => "Acmei Name", "Domains" => "a.coop" } ]) ]
    priorities = { "default" => [ "ica" ], "name" => [ "ica" ] }

    rows, = unify(settings(tables, priorities: priorities), cleaned)
    assert_equal [ "Acmei Name", "ica desc" ], rows.first.values_at("Name", "Description"),
      "Name from acmei; Description from ica, the first with a value"

    rows, = unify(settings(tables, priorities: priorities), cleaned, respect_field_priorities: true)
    assert_equal "Ica Name", rows.first["Name"]
  end

  test "writes data-pipelines' columns, with include_cols ordered by table" do
    s = settings({ "wc" => { "source" => "w", "include_cols" => [ "CUK ID" ] },
                   "dc" => { "source" => "d", "include_cols" => [ "Domains" ] } }, match_on: [ "Domains" ])
    cleaned = [ table("wc", [ { "Identifier" => "1", "Name" => "A" } ]), table("dc", [ { "Identifier" => "2", "Name" => "B" } ]) ]
    _rows, _stats, text = unify(s, cleaned)
    assert_equal "Identifier,Name,Description,Website,Primary Activity,Organisational Structure,Membership Type," \
                 "UC Country ID,Source Latitude,Source Longitude,Geo Container Latitude,Geo Container Longitude," \
                 "Geo Container,Geocoded Address,Region,dc.Domains,wc.CUK ID,Domains,Memberships,Identifiers," \
                 "Country ID,Latitude,Longitude", text.lines.first.chomp
  end

  test "lowercases Country ID and prefers the source location over the geocoded one" do
    s = settings({ "ica" => { "source" => "i" } }, match_on: [ "Domains" ])
    cleaned = [ table("ica", [
      { "Identifier" => "1", "Name" => "A", "Country ID" => "GB", "Latitude" => "51.50", "Longitude" => "-1",
        "Geo Container Latitude" => "50", "Geo Container Longitude" => "2" },
      { "Identifier" => "2", "Name" => "B", "Country ID" => "FR", "Geo Container Latitude" => "48.8", "Geo Container Longitude" => "2.3" }
    ]) ]
    rows, = unify(s, cleaned)
    assert_equal [ "GB", "gb", "51.5", "-1", "51.5", "-1", "50.0" ],
      rows[0].values_at("UC Country ID", "Country ID", "Source Latitude", "Source Longitude", "Latitude", "Longitude", "Geo Container Latitude")
    assert_equal [ "fr", "48.8", "2.3" ], rows[1].values_at("Country ID", "Latitude", "Longitude")
  end

  test "keeps integer coordinates as integers when the whole column is integral" do
    s = settings({ "usfwc" => { "source" => "u" } }, match_on: [ "Domains" ])
    rows, = unify(s, [ table("usfwc", [ { "Identifier" => "1", "Name" => "A", "Latitude" => "33", "Longitude" => "-117" } ]) ])
    assert_equal [ "33", "-117" ], rows.first.values_at("Latitude", "Longitude")
  end

  test "orders by name ignoring case, then identifier, unnamed last" do
    s = settings({ "ica" => { "source" => "i" } }, match_on: [ "Domains" ])
    names = { "3" => "beta", "1" => "Alpha", "2" => "beta", "4" => nil, "5" => "alpha" }
    rows, = unify(s, [ table("ica", names.map { |id, name| { "Identifier" => id, "Name" => name } }) ])
    assert_equal %w[ ica/1 ica/5 ica/2 ica/3 ica/4 ], rows.map { |row| row["Identifier"] }
  end

  test "a source's duplicates in one group contribute only the lowest identifier" do
    s = settings({ "dc" => { "source" => "d", "match" => DOMAINS } })
    cleaned = [ table("dc", [ { "Identifier" => "b", "Name" => "B", "Domains" => "x.coop" },
                              { "Identifier" => "a", "Name" => "A", "Description" => "from a", "Domains" => "x.coop" } ]) ]
    rows, stats = unify(s, cleaned)
    assert_equal 1, rows.size
    assert_equal [ "dc/a", "A", "dc=a" ], rows.first.values_at("Identifier", "Name", "Identifiers")
    assert_equal 1, stats[:merged]
  end

  test "writes empty values bare" do
    s = settings({ "ica" => { "source" => "i" } }, match_on: [ "Domains" ])
    _rows, _stats, text = unify(s, [ table("ica", [ { "Identifier" => "1", "Name" => "A" } ]) ])
    assert_equal "ica/1,A,,,,,,,,,,,,,,,ICA,ica=1,,,", text.lines.last.chomp
  end
end
