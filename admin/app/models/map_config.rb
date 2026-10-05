# A project's MykoMap config in admin/mykomaps/<project key>/: config.json
# (overrides merged onto the shared base.json), about.md and assets/.
# Mirrors data-pipelines' packages/dataset-build/mykomap/base.json and
# apps/<app>/mykomap/.
class MapConfig
  ROOT = Rails.root.join("mykomaps")

  attr_reader :key, :root

  # The project's map config, or nil if it has none.
  def self.for(key, root: ROOT)
    map = new(key, root: root)
    map.overlay_path.file? ? map : nil
  end

  # data-pipelines merge-mykomap-config: plain objects merge recursively,
  # arrays and scalars in the overlay replace the base, null removes a key.
  def self.merge(base, overlay)
    return overlay unless base.is_a?(Hash) && overlay.is_a?(Hash)
    overlay.each_with_object(base.dup) do |(key, value), out|
      if value.nil?
        out.delete(key)
      else
        out[key] = out.key?(key) ? merge(out[key], value) : value
      end
    end
  end

  # JSON text as data-pipelines writes it: JSON.stringify with 2-space
  # indent, JavaScript number formatting and a final newline.
  def self.json_text(value)
    Mykomap::JsJson.pretty_generate(value) + "\n"
  end

  def initialize(key, root: ROOT)
    @key = key
    @root = Pathname.new(root)
  end

  def dir
    root + key
  end

  def overlay_path
    dir + "config.json"
  end

  def about_path
    dir + "about.md"
  end

  def assets_dir
    dir + "assets"
  end

  def asset_files
    return [] unless assets_dir.directory?
    Pathname.glob(assets_dir + "**/*").select(&:file?).sort
  end

  def config
    self.class.merge(JSON.parse(File.read(root + "base.json")), JSON.parse(File.read(overlay_path)))
  end
end
