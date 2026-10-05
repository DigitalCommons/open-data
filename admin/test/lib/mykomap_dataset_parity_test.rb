require "test_helper"

# The CWM sample's unified CSV, built into a dataset by the monolith's own
# `dataset import` (mykomap-monolith 4.1.0, as data-pipelines pins it)
# with the merged CWM config, gives expected-dataset/; the Ruby writer must
# reproduce it byte for byte.
class MykomapDatasetParityTest < ActiveSupport::TestCase
  SAMPLE = Rails.root.join("test/fixtures/files/unified_csv/cwm-sample")

  test "builds the CWM sample dataset exactly as the monolith does" do
    merged = JSON.parse(File.read(SAMPLE + "merged-config.json"))
    Dir.mktmpdir do |tmp|
      out = File.join(tmp, "dataset")
      Mykomap::DatasetBuilder.build_dataset_from_csv(Mykomap::Config.parse(merged), (SAMPLE + "expected-unified.csv").to_s, out)
      File.write(File.join(out, "config.json"), MapConfig.json_text(merged))

      expected = SAMPLE + "expected-dataset"
      files = Dir.glob("**/*", base: expected).select { |path| File.file?(expected + path) }.sort
      assert_equal 23, files.size
      files.each do |path|
        assert_equal File.read(expected + path), File.read(File.join(out, path)), path
      end
    end
  end
end
