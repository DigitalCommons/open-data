require "test_helper"

# A slice of real CWM sources (standard.csv rows for 12 merged groups and
# 8 single rows, taken 2026-10-04) cleaned and unified by data-pipelines
# (main at 4c150b5) gives expected-unified.csv; the Ruby port must
# reproduce it byte for byte from the same inputs and projects.yml settings.
class UnifiedCsv::DataPipelinesParityTest < ActiveSupport::TestCase
  SAMPLE = Rails.root.join("test/fixtures/files/unified_csv/cwm-sample")

  test "cleans and unifies the CWM sample exactly as data-pipelines does" do
    settings = UnifySettings.from_definition(Project.project_definitions.dig("cwm", "unify"))
    Dir.mktmpdir do |dir|
      cleaned = settings.tables.to_h do |table|
        path = File.join(dir, "#{table.code}.cleaned.csv")
        UnifiedCsv::Cleaner.new(code: table.code, row_filter: table.row_filter)
          .clean(SAMPLE.join("standard", "#{table.code}.csv"), path)
        [ table.code, path ]
      end
      output = File.join(dir, "unified.csv")
      UnifiedCsv::Unifier.new(settings, cleaned).unify(output)

      assert_equal File.read(SAMPLE.join("expected-unified.csv")), File.read(output)
    end
  end
end
