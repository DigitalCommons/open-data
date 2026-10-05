# A key or password the data sources need (see db/secrets.yml), saved
# encrypted. A saved value always wins over the environment; values found
# in the environment are saved on start (seed_from_env!) and marked so.
class Secret < ApplicationRecord
  encrypts :value

  validates :key, presence: true, uniqueness: true
  validates :value, presence: true

  DEFINITIONS_FILE = "db/secrets.yml".freeze

  Definition = Data.define(:key, :path, :name, :description, :where) do
    # se-open-data's PasswordStore naming
    def env_var
      "PASSWORD__#{path.upcase.tr('^A-Z0-9_', '_')}"
    end

    # Source directories whose conf files name this secret's path.
    def used_by
      Dir.glob(OpenData.root + "*/{default,production,staging}.conf")
        .select { |conf| File.read(conf).match?(/^\s*[A-Z_]+_PATH\s*=\s*#{Regexp.escape(path)}\s*$/) }
        .map { |conf| File.basename(File.dirname(conf)) }.uniq.sort
    end
  end

  def self.definitions
    YAML.load_file(Rails.root.join(DEFINITIONS_FILE)).map do |key, info|
      Definition.new(key: key, path: info.fetch("path"), name: info.fetch("name"),
        description: info.fetch("description"), where: info.fetch("where"))
    end
  end

  def self.definition(key)
    definitions.find { |definition| definition.key == key }
  end

  def self.seed_from_env!(env = ENV)
    definitions.each do |definition|
      value = env[definition.env_var]
      next if value.blank? || exists?(key: definition.key)
      create!(key: definition.key, value: value, from_env: true)
    end
  end

  # PASSWORD__ variables for the saved values, for download runs.
  def self.env
    by_key = all.index_by(&:key)
    definitions.each_with_object({}) do |definition, env|
      secret = by_key[definition.key]
      env[definition.env_var] = secret.value if secret
    end
  end

  def self.status(key)
    secret = find_by(key: key)
    return "Not set" unless secret
    origin = secret.from_env? ? "from environment" : "saved #{ApplicationController.helpers.time_ago_in_words(secret.updated_at)} ago"
    "Set, ends in …#{secret.value.last(4)}, #{origin}"
  end
end
