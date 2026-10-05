require "test_helper"
require "csv"

class RowStampsTest < ActiveSupport::TestCase
  T1 = Time.utc(2026, 10, 1, 9, 0, 0)
  T2 = Time.utc(2026, 10, 5, 12, 30, 0)

  setup { @dir = Pathname.new(Dir.mktmpdir("row-stamps")) }
  teardown { FileUtils.remove_entry(@dir) }

  def write(name, text)
    (@dir + name).tap { |path| File.write(path, text) }
  end

  def rows(path)
    CSV.read(path, headers: true).map(&:to_h)
  end

  test "stamps every row of a first version with the given time" do
    path = write("new.csv", "Identifier,Name\n1,One\n2,Two\n")
    result = RowStamps.apply(path, previous_path: nil, at: T1)

    assert_equal "Identifier,Name,Created At,Updated At\n1,One,2026-10-01T09:00:00Z,2026-10-01T09:00:00Z\n2,Two,2026-10-01T09:00:00Z,2026-10-01T09:00:00Z\n",
      File.read(path)
    assert_equal({ added: 2, changed: 0, unchanged: 0, untracked: 0 }, result)
  end

  test "keeps dates for unchanged rows, updates changed rows and dates new ones" do
    previous = write("old.csv", "Identifier,Name,Created At,Updated At\n1,One,2026-09-01T00:00:00Z,2026-09-02T00:00:00Z\n2,Two,2026-09-01T00:00:00Z,2026-09-01T00:00:00Z\n3,Gone,2026-09-01T00:00:00Z,2026-09-01T00:00:00Z\n")
    path = write("new.csv", "Identifier,Name\n1,One\n2,Two renamed\n4,Four\n")
    result = RowStamps.apply(path, previous_path: previous, at: T2)

    stamps = rows(path).to_h { |row| [ row["Identifier"], row.values_at("Created At", "Updated At") ] }
    assert_equal [ "2026-09-01T00:00:00Z", "2026-09-02T00:00:00Z" ], stamps["1"]
    assert_equal [ "2026-09-01T00:00:00Z", "2026-10-05T12:30:00Z" ], stamps["2"]
    assert_equal [ "2026-10-05T12:30:00Z", "2026-10-05T12:30:00Z" ], stamps["4"]
    assert_equal({ added: 1, changed: 1, unchanged: 1, untracked: 0 }, result)
  end

  test "replaces stamp columns already in the new file and ignores them when comparing" do
    previous = write("old.csv", "Identifier,Name,Created At,Updated At\n1,One,2026-09-01T00:00:00Z,2026-09-01T00:00:00Z\n")
    path = write("new.csv", "Identifier,Created At,Name,Updated At\n1,x,One,y\n")
    RowStamps.apply(path, previous_path: previous, at: T2)
    assert_equal "Identifier,Name,Created At,Updated At\n1,One,2026-09-01T00:00:00Z,2026-09-01T00:00:00Z\n", File.read(path)
  end

  test "a previous version without stamps dates its matched rows at the given time" do
    previous = write("old.csv", "Identifier,Name\n1,One\n")
    path = write("new.csv", "Identifier,Name\n1,One\n")
    result = RowStamps.apply(path, previous_path: previous, at: T2)
    assert_equal [ "2026-10-05T12:30:00Z" ] * 2, rows(path).first.values_at("Created At", "Updated At")
    assert_equal 1, result[:unchanged]
  end

  test "rows with a blank or repeated Identifier cannot be tracked and are dated now" do
    previous = write("old.csv", "Identifier,Name,Created At,Updated At\n1,One,2026-09-01T00:00:00Z,2026-09-01T00:00:00Z\n")
    path = write("new.csv", "Identifier,Name\n,No id\n1,One\n1,One again\n")
    result = RowStamps.apply(path, previous_path: previous, at: T2)
    assert_equal [ "2026-10-05T12:30:00Z" ] * 3, rows(path).map { |row| row["Updated At"] }
    assert_equal 3, result[:untracked]
  end

  test "a row can inherit the earliest Created At of the previous rows it absorbs" do
    previous = write("old.csv", "Identifier,Identifiers,Created At,Updated At\ncuk/5,cuk=5,2026-08-01T00:00:00Z,2026-08-01T00:00:00Z\ndc/9,dc=9,2026-07-01T00:00:00Z,2026-07-02T00:00:00Z\n")
    path = write("new.csv", "Identifier,Identifiers\nacmei/1,acmei=1;cuk=5;dc=9\n")
    members = ->(row) { row["Identifiers"].to_s.split(";").map { |pair| pair.sub("=", "/") } }
    result = RowStamps.apply(path, previous_path: previous, at: T2, members: members)

    assert_equal [ "2026-07-01T00:00:00Z", "2026-10-05T12:30:00Z" ], rows(path).first.values_at("Created At", "Updated At")
    assert_equal 1, result[:changed]
  end

  test "with no previous version, rows can be seeded from their members' dates" do
    path = write("new.csv", "Identifier,Identifiers\ncuk/5,cuk=5;dc=9\nica/7,ica=7\n")
    members = ->(row) { row["Identifiers"].to_s.split(";").map { |pair| pair.sub("=", "/") } }
    seed = { "cuk/5" => [ "2026-08-01T00:00:00Z", "2026-09-01T00:00:00Z" ], "dc/9" => [ "2026-07-01T00:00:00Z", "2026-07-05T00:00:00Z" ] }
    RowStamps.apply(path, previous_path: nil, at: T2, members: members, seed: seed)

    stamped = rows(path).map { |row| row.values_at("Created At", "Updated At") }
    assert_equal [ "2026-07-01T00:00:00Z", "2026-09-01T00:00:00Z" ], stamped[0]
    assert_equal [ T2.iso8601, T2.iso8601 ], stamped[1], "no member dates known"
  end

  test "a previous version without dates lets seed dates apply to matched rows" do
    previous = write("old.csv", "Identifier,Identifiers\ncuk/5,cuk=5\n")
    path = write("new.csv", "Identifier,Identifiers\ncuk/5,cuk=5\n")
    members = ->(row) { row["Identifiers"].to_s.split(";").map { |pair| pair.sub("=", "/") } }
    RowStamps.apply(path, previous_path: previous, at: T2, members: members, seed: { "cuk/5" => [ "2026-08-01T00:00:00Z", "2026-08-03T00:00:00Z" ] })
    assert_equal [ "2026-08-01T00:00:00Z", "2026-08-03T00:00:00Z" ], rows(path).first.values_at("Created At", "Updated At")
  end
end
