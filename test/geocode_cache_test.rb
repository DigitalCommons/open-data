require "minitest/autorun"
require "tmpdir"
require_relative "../lib/geocode_cache"

class GeocodeCacheTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "cache", "geocodes.csv")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_missing_file_is_an_empty_cache
    cache = GeocodeCache.new(@path)

    assert_equal 0, cache.size
    assert_nil cache["anywhere"]
  end

  def test_round_trips_entries_through_the_csv_file
    cache = GeocodeCache.new(@path)
    cache["1 High St, Brecon, GB"] = GeocodeCache::Entry.new("51.9", "-3.4", "Brecon, Wales")
    cache.save

    reloaded = GeocodeCache.new(@path)
    assert_equal 1, reloaded.size
    assert_equal GeocodeCache::Entry.new("51.9", "-3.4", "Brecon, Wales"),
                 reloaded["1 High St, Brecon, GB"]
  end

  def test_keeps_the_data_pipelines_layout
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path,
               "query,lat,lng,geocodedAddress\n" \
               "\"Newgate Street, Brecon, LD3 8ED, GB\",51.944891,-3.407428,\"LD3 8ED, Brecon\"")
    cache = GeocodeCache.new(@path)
    cache.save

    assert_equal "query,lat,lng,geocodedAddress\n" \
                 "\"Newgate Street, Brecon, LD3 8ED, GB\",51.944891,-3.407428,\"LD3 8ED, Brecon\"",
                 File.read(@path)
  end

  def test_ignores_rows_without_a_query
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path, "query,lat,lng,geocodedAddress\n,1,2,nowhere\n")

    assert_equal 0, GeocodeCache.new(@path).size
  end
end
