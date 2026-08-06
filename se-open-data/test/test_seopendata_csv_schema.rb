require_relative "../lib/load_path"
require "se_open_data/csv/schema"
require "minitest/autorun"

Minitest::Test::make_my_diffs_pretty!

describe SeOpenData::CSV::Schema do
  
  describe "a typical instance" do

    schema = SeOpenData::CSV::Schema.new(
      id: :schema1,
      name: "Schema 1",
      fields: [
        {id: :apples,
         header: "Apples",
         desc: "A fruit",
         comment: <<~HERE
           Apples grow on trees.
           They are sometimes green.
HERE
        },
        {id: "brussels sprouts",
         header: "Brussels Sprouts"},
        {id: :carrots,
         header: "Carrots"},
      ]
    )

    it "should have the expected attributes" do
      value(schema.id).must_equal :schema1
      value(schema.name).must_equal "Schema 1"
      value(schema.fields.size).must_equal 3
      value(schema.fields[0].id).must_equal :apples
      value(schema.fields[1].id).must_equal :'brussels sprouts'
      value(schema.fields[2].id).must_equal :carrots
      value(schema.fields[0].header).must_equal "Apples"
      value(schema.fields[1].header).must_equal "Brussels Sprouts"
      value(schema.fields[2].header).must_equal "Carrots"
      value(schema.fields[0].desc).must_equal "A fruit"
      value(schema.fields[1].desc).must_equal ""
      value(schema.fields[2].desc).must_equal ""
      value(schema.fields[0].comment).must_equal "Apples grow on trees.\nThey are sometimes green.\n"
      value(schema.fields[1].comment).must_equal ""
      value(schema.fields[2].comment).must_equal ""
      value(schema.field_ids).must_equal [:apples, :'brussels sprouts', :carrots]
      value(schema.field_headers).must_equal %w(Apples Brussels\ Sprouts Carrots)
    end

    it "should implement #validate_headers" do
      value(schema.validate_headers(%w(Apples Brussels\ Sprouts Carrots)))
        .must_equal([0,1,2])
      value(schema.validate_headers(%w(Brussels\ Sprouts Carrots Apples)))
        .must_equal([2,0,1])
      value(schema.validate_headers(%w(Apples Carrots Brussels\ Sprouts)))
        .must_equal([0,2,1])
      # Extra fields get ignored
      value(schema.validate_headers(%w(Apples Carrots Brussels\ Sprouts Cucumbers)))
        .must_equal([0,2,1])
      # Duplicate fields not allowed
      value(assert_raises(ArgumentError) {
              schema.validate_headers(%w(Apples Carrots Brussels\ Sprouts Apples))
            }.message).must_match 'header fields are invalid'
      
      # Missing fields not allowed
      value(assert_raises(ArgumentError) {
              schema.validate_headers(%w(Apples Carrots))
            }.message).must_match 'header fields are invalid'
    end

    it "should implement #id_hash" do
      # Note, arg #1 to id_hash is a list of data fields, arg #2 is a list
      # of data field indexes, one per schema field.
      
      # Check field mapping works
      value(schema.id_hash(%w(a b c), [0,1,2])).must_equal({apples: 'a',
                                                            'brussels sprouts': 'b',
                                                            carrots: 'c'})
      value(schema.id_hash(%w(a b c), [2,0,1])).must_equal({apples: 'c',
                                                            'brussels sprouts': 'a',
                                                            carrots: 'b'})
      # Invalid fields not allowed
      value(assert_raises(ArgumentError) {
              schema.id_hash(%w(a b c), [2,0,3])
            }.message).must_match 'does not include the field index 3'
      value(assert_raises(ArgumentError) {
              schema.id_hash(%w(a b c), [2,0,-1])
            }.message).must_match 'does not include the field index -1'
      
      # Duplicate fields not allowed
      value(assert_raises(ArgumentError) {
              schema.id_hash(%w(a b c), [2,2,0])
            }.message).must_match 'duplicate field index 2'
    end

    it "should implement #row" do
      value(schema.row({apples: 'a',
                        'brussels sprouts': 'b',
                        carrots: 'c'})).must_equal %w(a b c)
      value(schema.row({apples: 'b',
                        'brussels sprouts': 'c',
                        carrots: 'a'})).must_equal %w(b c a)

      # Unknown ids are errors
      value(assert_raises(ArgumentError) {
              schema.row({apples: 'b',
                          'brussels sprouts': 'c',
                          carrots: 'a',
                          cucumbers: 'a'})
            }.message
           ).must_match "these hash keys do not match any field IDs of schema 'schema1': cucumbers"

      # All fields must be present
      value(assert_raises(ArgumentError) {
              schema.row({apples: 'b',
                          carrots: 'a'})
            }.message).must_match "no value for field 'brussels sprouts'"
    end
  end
  
end

