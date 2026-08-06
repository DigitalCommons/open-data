require "test_helper"

class CsvDiffTest < ActiveSupport::TestCase
  def write_csv(dir, name, rows)
    path = File.join(dir, name)
    File.write(path, "Identifier,Name,Website\n" + rows.map { |r| r.join(",") }.join("\n") + "\n")
    path
  end

  test "first download reports all rows added" do
    Dir.mktmpdir do |dir|
      new_csv = write_csv(dir, "new.csv", [ [ 1, "One", "" ], [ 2, "Two", "" ] ])
      result = CsvDiff.call(nil, new_csv)
      assert_equal 2, result.added
      assert_equal 0, result.removed
      assert_equal 0, result.changed
      assert_match(/First download: 2 rows/, result.summary)
    end
  end

  test "detects added, removed and changed rows" do
    Dir.mktmpdir do |dir|
      old_csv = write_csv(dir, "old.csv", [ [ 1, "One", "a" ], [ 2, "Two", "b" ], [ 3, "Three", "c" ] ])
      new_csv = write_csv(dir, "new.csv", [ [ 1, "One", "a" ], [ 2, "Two renamed", "b" ], [ 4, "Four", "d" ] ])
      result = CsvDiff.call(old_csv, new_csv)
      assert_equal 1, result.added
      assert_equal 1, result.removed
      assert_equal 1, result.changed
      assert_equal "1 added, 1 removed, 1 changed (3 rows, was 3).", result.summary
      assert_match(/\+ 4: Four/, result.detail)
      assert_match(/- 3: Three/, result.detail)
      assert_match(/~ 2: Name/, result.detail)
    end
  end

  test "identical files report no differences" do
    Dir.mktmpdir do |dir|
      old_csv = write_csv(dir, "old.csv", [ [ 1, "One", "a" ] ])
      new_csv = write_csv(dir, "new.csv", [ [ 1, "One", "a" ] ])
      result = CsvDiff.call(old_csv, new_csv)
      assert_equal [ 0, 0, 0 ], [ result.added, result.removed, result.changed ]
      assert_match(/No differences/, result.detail)
    end
  end

  test "detail is truncated for very large diffs" do
    Dir.mktmpdir do |dir|
      old_csv = write_csv(dir, "old.csv", [ [ 0, "Zero", "" ] ])
      rows = (1..600).map { |i| [ i, "Name #{i}", "" ] }
      new_csv = write_csv(dir, "new.csv", rows)
      result = CsvDiff.call(old_csv, new_csv)
      assert_equal 600, result.added
      assert_match(/truncated, 601 differences in total/, result.detail)
      assert_operator result.detail.lines.size, :<=, CsvDiff::MAX_DETAIL_LINES + 1
    end
  end
end
