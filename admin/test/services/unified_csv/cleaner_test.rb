require "csv"
require "test_helper"

# Expected behaviour is data-pipelines' packages/dataset-build clean-csv-data.ts.
class UnifiedCsv::CleanerTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname.new(Dir.mktmpdir("cleaner-test"))
    @log = []
  end

  teardown { FileUtils.remove_entry(@dir) }

  def clean(csv, code: "ica", row_filter: {})
    input = @dir + "in.csv"
    output = @dir + "out.csv"
    File.write(input, csv)
    UnifiedCsv::Cleaner.new(code: code, row_filter: row_filter, log: @log).clean(input, output)
    File.read(output)
  end

  def cleaned_rows(...)
    CSV.parse(clean(...), headers: true).map(&:to_h)
  end

  def messages
    @log.map { |entry| entry[:message] }
  end

  test "appends Domains and Dataset columns, keeping an existing Domains in place" do
    assert_equal "Identifier,Name,Domains,Dataset\n1,One,,ica\n", clean("Identifier,Name\n1,One\n")
    assert_equal "Identifier,Domains,Name,Dataset\n1,a.coop,One,ica\n", clean("Identifier,Domains,Name\n1,a.coop,One\n")
    assert_equal "Identifier,Name,Domains,Dataset\n1,One,,ica\n", clean("Identifier,Dataset,Name\n1,old,One\n")
  end

  test "writes empty values unquoted and quotes only when needed" do
    out = clean("Identifier,Name,Description\n1,\"Smith, Jones\",\"say \"\"hi\"\"\"\n2,,\n")
    assert_equal "Identifier,Name,Description,Domains,Dataset\n1,\"Smith, Jones\",\"say \"\"hi\"\"\",,ica\n2,,,,ica\n", out
  end

  test "derives sorted unique registrable domains from Website" do
    rows = cleaned_rows("Identifier,Website\n1,https://www.b.coop/;a.coop;http://shop.a.coop\n2,example.co.uk\n3,\n")
    assert_equal "a.coop;b.coop", rows[0]["Domains"]
    assert_equal "example.co.uk", rows[1]["Domains"]
    assert_nil rows[2]["Domains"]
  end

  test "keeps a Domains value the source supplied" do
    rows = cleaned_rows("Identifier,Website,Domains\n1,https://other.coop,given.coop\n")
    assert_equal "given.coop", rows[0]["Domains"]
  end

  test "rejects website parts with paths, spaces, commas or no public suffix" do
    rows = cleaned_rows("Identifier,Website\n1,\"http://x.coop/about;bad url;a,b.coop;http://foo.notatld;http://10.0.0.1;\"\n")
    assert_equal "", rows[0]["Domains"].to_s
    assert_includes messages, "url must not have path"
    assert_equal 3, messages.count("invalid url"), "space, comma and the empty part"
    assert_equal 2, messages.count("non-icann domain")
  end

  test "ignores query strings and fragments when checking for a path" do
    rows = cleaned_rows("Identifier,Website\n1,https://x.coop?lang=en\n2,https://y.coop/#top\n")
    assert_equal [ "x.coop", "y.coop" ], rows.map { |row| row["Domains"] }
  end

  test "whitelisted domains are kept even with a path; blacklisted ones are dropped" do
    rows = cleaned_rows("Identifier,Website\n1,https://outpost.coop/store\n2,https://myco.blogspot.com\n")
    assert_equal "outpost.coop", rows[0]["Domains"]
    assert_equal "", rows[1]["Domains"].to_s
    assert_includes messages, "including whitelisted domain"
    assert_includes messages, "excluding blacklisted domain"
  end

  test "zaps unknown Organisational Structure terms and strips vocab URIs" do
    csv = <<~CSV
      Identifier,Organisational Structure,Primary Activity,Activities,Country ID
      1,https://dev.lod.coop/essglobal/2.1/standard/organisational-structure/OS115,https://example.org/x/ICA230,http://a/b/ICA140;http://a/b/ICA210,https://example.org/c/GB
      2,OS999,,,
    CSV
    rows = cleaned_rows(csv)
    assert_equal [ "OS115", "ICA230", "ICA140;ICA210", "GB" ], rows[0].values_at("Organisational Structure", "Primary Activity", "Activities", "Country ID")
    assert_nil rows[1]["Organisational Structure"]
    assert_includes messages, 'unsupported Organisational Structure term, zapping: "OS999"'
    assert_includes messages, 'no value of "Country ID"'
  end

  test "trims text fields with JavaScript's notion of whitespace" do
    rows = cleaned_rows("Identifier,Name,Locality,Description\n 1 , One　, Town ,\tdesc\n")
    assert_equal [ "1", "One", "Town", "desc" ], rows[0].values_at("Identifier", "Name", "Locality", "Description")
  end

  test "normalises US regions to USPS codes, falling back to the geocoded address" do
    csv = <<~CSV
      Identifier,Country ID,Region,Geocoded Address
      1,US,Minnesota,
      2,us,,"123 Main St, Minneapolis, MN 55414, United States"
      3,USA,mn.,
      4,GB,Minnesota,
      5,US,Nowhere,
    CSV
    assert_equal [ "MN", "MN", "MN", "Minnesota", "Nowhere" ], cleaned_rows(csv).map { |row| row["Region"] }
  end

  test "DotCoop: blanks Website, re-tags sector and category, lowercases country" do
    csv = "Identifier,Website,Economic Sector ID,Organisational Category ID,Country ID\n1,a.coop,Z7_gE:20,l1cbA:42,IT\n"
    row = cleaned_rows(csv, code: "dc").first
    assert_nil row["Website"]
    assert_equal "a.coop", row["Domains"]
    assert_equal [ "ES20", "OC42", "it" ], row.values_at("Economic Sector ID", "Organisational Category ID", "Country ID")
  end

  test "workers.coop: prefixes its numeric vocab keys" do
    csv = "Identifier,Registered Status,Industry,Ownership Classification,Legal Form\n1,1,7,2,\n"
    row = cleaned_rows(csv, code: "wc").first
    assert_equal [ "RS1", "IND7", "OT2", nil ], row.values_at("Registered Status", "Industry", "Ownership Classification", "Legal Form")
  end

  test "row filter drops rows whose raw values do not match" do
    csv = "Identifier,Registered Status\n1,1\n2,3\n3,1\n"
    rows = cleaned_rows(csv, code: "wc", row_filter: { "Registered Status" => "1" })
    assert_equal [ "1", "3" ], rows.map { |row| row["Identifier"] }
  end

  test "returns the number of rows written" do
    input = @dir + "in.csv"
    File.write(input, "Identifier\n1\n2\n")
    assert_equal 2, UnifiedCsv::Cleaner.new(code: "ica").clean(input, @dir + "out.csv")
  end
end
