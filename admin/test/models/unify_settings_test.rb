require "test_helper"

class UnifySettingsTest < ActiveSupport::TestCase
  def cwm
    UnifySettings.from_definition(Project.project_definitions.dig("cwm", "unify"))
  end

  test "parses tables in file order with their match columns" do
    settings = UnifySettings.from_definition(
      "match_on" => [ "Domains", "CUK ID" ],
      "field_priorities" => { "default" => [ "b" ], "name" => [ "a" ] },
      "tables" => {
        "b" => { "source" => "beta", "match" => { "Domains" => "Domains", "CUK ID" => "Identifier" },
                 "include_cols" => [ "Domains" ], "row_filter" => { "Registered Status" => "1" } },
        "a" => { "source" => "alpha" }
      }
    )

    assert_equal [ "Domains", "CUK ID" ], settings.match_on
    assert_equal [ "b", "a" ], settings.tables.map(&:code)
    b = settings.table("b")
    assert_equal "beta", b.source
    assert_equal({ "Domains" => "Domains", "CUK ID" => "Identifier" }, b.match)
    assert_equal [ "Domains" ], b.include_cols
    assert_equal({ "Registered Status" => "1" }, b.row_filter)
    a = settings.table("a")
    assert_equal({}, a.match)
    assert_equal [], a.include_cols
    assert_equal({}, a.row_filter)
    assert_equal({ "default" => [ "b" ], "name" => [ "a" ] }, settings.field_priorities)
  end

  test "rejects a match column that is not in match_on" do
    error = assert_raises(ArgumentError) do
      UnifySettings.from_definition("match_on" => [ "Domains" ],
        "tables" => { "a" => { "source" => "alpha", "match" => { "CUK ID" => "CUK ID" } } })
    end
    assert_match(/CUK ID/, error.message)
  end

  test "CWM matches data-pipelines' cwm-data defs" do
    settings = cwm
    assert_equal [ "Domains", "CUK ID" ], settings.match_on
    assert_equal %w[ acmei cmc cooperar cuk dc eurocoop fca ficu ica ics iffco ncba ncg ncui usda usfwc wc ycc nfca comn ],
      settings.tables.map(&:code)
    assert_equal({ "Domains" => "Domains", "CUK ID" => "Identifier" }, settings.table("cuk").match)
    assert_equal({ "Domains" => "Domains", "CUK ID" => "CUK ID" }, settings.table("wc").match)
    assert_equal [ "Domains" ], settings.table("dc").include_cols
    assert_equal({}, settings.table("fca").match)
    assert_equal({ "default" => %w[ ica cuk dc ncba ], "name" => %w[ ica dc cuk ncba ] }, settings.field_priorities)
  end

  test "Workers.coop keeps Live co-ops only" do
    settings = UnifySettings.from_definition(Project.project_definitions.dig("workers-coop", "unify"))
    assert_equal({ "Registered Status" => "1" }, settings.table("wc").row_filter)
  end

  test "every unify table names a source listed in its project" do
    Project.project_definitions.each do |key, info|
      next unless info["unify"]
      settings = UnifySettings.from_definition(info["unify"])
      assert_empty settings.tables.map(&:source) - Array(info["sources"]), "#{key} unifies a source it does not list"
    end
  end
end
