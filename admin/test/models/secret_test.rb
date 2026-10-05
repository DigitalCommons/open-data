require "test_helper"

class SecretTest < ActiveSupport::TestCase
  test "definitions name each secret's environment variable from its password path" do
    geoapify = Secret.definition("geoapify")
    assert_equal "PASSWORD__GEOAPIFYAPI_TXT", geoapify.env_var
    assert_equal "Geoapify API key", geoapify.name
    assert_equal "PASSWORD__ACCOUNTS_AIRTABLE_COM_DATA_FACTORY_DOWNLOAD_APIKEY", Secret.definition("airtable").env_var
  end

  test "every secret path in the source configs has a definition" do
    paths = Dir.glob(Rails.root.join("../*/{default,production,staging}.conf")).flat_map do |conf|
      File.readlines(conf).filter_map { |line| line[/^\s*[A-Z_]*(?:KEY|PASSWORD|PAT|TOKEN)_PATH\s*=\s*(\S+)/, 1] }
    end
    assert_empty paths.uniq - Secret.definitions.map(&:path)
  end

  test "definitions list the sources whose configs use them" do
    assert_includes Secret.definition("airtable").used_by, "owned-by-oxford"
    assert_includes Secret.definition("mapbox").used_by, "powys-eng"
  end

  test "values are encrypted in the database" do
    Secret.create!(key: "geoapify", value: "plain-geo-key-1234")
    raw = Secret.connection.select_value("SELECT value FROM secrets WHERE key = 'geoapify'")
    assert_not_includes raw, "plain-geo-key-1234"
    assert_equal "plain-geo-key-1234", Secret.find_by!(key: "geoapify").value
  end

  test "seed_from_env! saves environment values only where nothing is saved" do
    Secret.create!(key: "mapbox", value: "saved-token")
    env = { "PASSWORD__GEOAPIFYAPI_TXT" => "env-geo", "PASSWORD__SERVICES_MAPBOX_LANDEXPLORER_TXT" => "env-mapbox" }
    Secret.seed_from_env!(env)

    assert_equal "env-geo", Secret.find_by!(key: "geoapify").value
    assert Secret.find_by!(key: "geoapify").from_env?
    assert_equal "saved-token", Secret.find_by!(key: "mapbox").value
    assert_nil Secret.find_by(key: "airtable")
  end

  test "env gives saved values under their PASSWORD__ names" do
    Secret.create!(key: "airtable", value: "pat123")
    assert_equal({ "PASSWORD__ACCOUNTS_AIRTABLE_COM_DATA_FACTORY_DOWNLOAD_APIKEY" => "pat123" }, Secret.env)
  end

  test "status shows the last four characters and where the value came from" do
    travel_to Time.utc(2026, 10, 5, 12) do
      Secret.create!(key: "geoapify", value: "abcdef1a2b", from_env: true)
      Secret.create!(key: "mapbox", value: "pk.zz9876", updated_at: 3.days.ago)
    end
    travel_to Time.utc(2026, 10, 5, 12) do
      assert_equal "Set, ends in …1a2b, from environment", Secret.status("geoapify")
      assert_equal "Set, ends in …9876, saved 3 days ago", Secret.status("mapbox")
      assert_equal "Not set", Secret.status("airtable")
    end
  end
end
