require "zip"

module Mykomap
  module Zip
    module_function

    # Zips a dataset dir's contents at the zip root (config.json at top
    # level - the layout the monolith's zip ingest accepts).
    def zip_dir(dir, zip_path)
      FileUtils.rm_f(zip_path)
      ::Zip::File.open(zip_path, create: true) do |zip|
        Dir.glob("**/*", base: dir).sort.each do |entry|
          full = File.join(dir, entry)
          File.directory?(full) ? zip.mkdir(entry) : zip.add(entry, full)
        end
      end
    end
  end
end
