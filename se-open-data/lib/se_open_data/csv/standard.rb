require 'se_open_data/csv/converter/limesurveycore'
require 'se_open_data/csv/schemas'

module SeOpenData
  module CSV
    # Here we define the standard column headings for CSV that we convert to Linked Data
    #
    # The symbols in these Headers hashes are used elsewhere in the SeOpenData library
    # in order to address the data in a CSV file, with an extra level of indirection,
    # removing the dependency on the text of the Column header.
    #
    # e.g. use
    #
    #     SeOpenData::CSV::Standard::V1::Headers[:postcode]
    #
    # instead of
    #
    #     "Postcode"
    #
    # So don't mess with the symbol names!!
    #
    # @deprecated - use SeOpenData::CSV:Schema#converter
    module Standard

      # Version one of the standard.
      module V1

        # Note - from ruby 1.9, keys and values are returned in
        # insertion order, so the headers Hash also defines the
        # ordering of the columns.
        #
        # [LATER] But beware: see this, which suggests it isn't
        # entirely guaranteed for hash literals in all
        # implementations.
        # https://stackoverflow.com/questions/31418673/is-order-of-a-ruby-hash-literal-guaranteed

        # Defines the header ids (keys) and text (values).
        Headers = SeOpenData::CSV::Schemas::Latest.to_h
        SubFieldSeparator = SeOpenData::CSV::Converter::LimeSurveyCore::SubFieldSeparator

        # Keys should provide unique access to the dataset (no dups)
        UniqueKeys = [:id]
      end
    end
  end
end
