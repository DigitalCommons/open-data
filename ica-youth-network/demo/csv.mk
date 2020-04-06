# This makefile is for turning Oxford Lime Survey results CSV into the standard format expected by se_open_data.
#
# Standard GNU make trick - see http://stackoverflow.com/a/7531247/685715
nullstring :=
space := $(nullstring) # end of the line

include common.mk
possible_editions := $(basename $(notdir $(wildcard $(EDITIONS_DIR)*.mk)))

ifndef edition
$(info )
$(info ERROR: The make command must set the edition of data to be generated using:)
$(info $(space)    make edition=<name>)
$(info This will cause the file <name>.mk to be included from the directory '$(EDITIONS_DIR)'.)
$(info Looking at .mk files in '$(EDITIONS_DIR)', possible values for <name> are:)
$(info $(space)    $(possible_editions))
$(error Stopping due to error.)
endif


# To configure a specific version - put variable definitions in the edition makefile fragment: 
include $(EDITIONS_DIR)$(edition).mk

CSV_target := csv
.PHONY: $(CSV_target)
.DEFAULT_GOAL := $(CSV_target)

# Source files:
ORIGINAL_CSV := $(SRC_CSV_DIR)Youth-led-Co-ops-Coops_new.csv

# Here's the directory where we generate intermediate csv files
GEN_CSV_DIR := $(TOP_OUTPUT_DIR)csv/

# This makefile controls a pipeline of processes that convert the original
# CSV data into the se_open_data standard, one step at a time.

# Intermediate CSV files
# hmm
STD_ORIGINAL_CSV := $(GEN_CSV_DIR)initiatives.csv
CLEARED_FILE := $(GEN_CSV_DIR)cleared.csv
# STD_ORGS_CSV := $(GEN_CSV_DIR)organisations.csv
# STD_MERGED_CSV := $(GEN_CSV_DIR)merged.csv
# STD_FIXED_DUPS_CSV := $(GEN_CSV_DIR)fixed-dups.csv
# STD_DE_DUPED_CSV := $(GEN_CSV_DIR)de-duplicated.csv
# STD_DUPS_CSV := $(GEN_CSV_DIR)ignored-duplicates.csv
# STD_URI_NAME_POSTCODE_CSV := $(GEN_CSV_DIR)uri-name-postcode.csv

# CSV report file (copy of the original, but with a column of comments added)
REPORT_CSV := $(GEN_CSV_DIR)report.csv


# Some local scripts to help with the conversion:
ORIGINAL_CONVERTER := converter.rb
CLEAR_CSV := clear_csv_errors.rb

# Scripts to be used in the pipeline:
# CSV_DUP_FIXER := $(SE_OPEN_DATA_BIN_DIR)csv/standard/fix-duplicates.rb
# CSV_DE_DUPER := $(SE_OPEN_DATA_BIN_DIR)csv/standard/remove-duplicates.rb
CSV_POSTCODEUNIT_ADDER := $(SE_OPEN_DATA_BIN_DIR)csv/standard/add-postcode-lat-long.rb
CSV_ADD_IDS := $(SE_OPEN_DATA_BIN_DIR)csv/standard/add-unique-id.rb
# URI_NAME_POSTCODE_RUBY := $(SE_OPEN_DATA_BIN_DIR)csv/standard/make-uri-name-postcode.rb

# The CSV_POSTCODEUNIT_ADDER script will convert postcodes into lat/long by 
# getting linked data over the web. This is (currently) a slow process (plenty of room for speed ups!)
# The POSTCODE_LAT_LNG_CACHE is a file for cacheing the results of these slow lookups.
POSTCODE_LAT_LNG_CACHE := postcode_lat_lng.json

RUBY := ruby -I $(SE_OPEN_DATA_LIB_DIR) 

####################
# The pipeline for processing CSV files for the Oxford project:

# Convert original csv to the standard csv:
# $(STD_ORIGINAL_CSV) : $(ORIGINAL_CSV) $(ORIGINAL_CONVERTER) | $(GEN_CSV_DIR)
# 	$(RUBY) $(ORIGINAL_CONVERTER) $(REPORT_CSV) $< > $@
$(CLEARED_FILE) : $(ORIGINAL_CSV) | $(GEN_CSV_DIR)
	$(RUBY) $(CLEAR_CSV) $< > $@

$(STD_ORIGINAL_CSV) : $(CLEARED_FILE) | $(GEN_CSV_DIR)
	$(RUBY) $(CSV_ADD_IDS) $< > $@

$(STANDARD_CSV) : $(STD_ORIGINAL_CSV) $(ORIGINAL_CONVERTER) | $(GEN_CSV_DIR)
	$(RUBY) $(ORIGINAL_CONVERTER) $< > $@
	
# Populate the container lat/long fields, where the postcodeunit is the container:
# $(STANDARD_CSV) : $(STD_ORIGINAL_CSV) | $(GEN_CSV_DIR)
# 	$(RUBY) $(CSV_POSTCODEUNIT_ADDER) --postcodeunit-cache $(POSTCODE_LAT_LNG_CACHE) $< > $@
# 	@echo "standard.csv"

# Create a CSV file from the STANDARD one with just a few columns: URI, Name and Normalized postcode
# $(STD_URI_NAME_POSTCODE_CSV): $(STANDARD_CSV) | $(GEN_CSV_DIR)
# 	$(RUBY) $(URI_NAME_POSTCODE_RUBY) --uri-prefix $(URI_SCHEME)://$(URI_HOST)/$(URI_PATH_PREFIX) $< > $@

####################
# Directories

$(GEN_CSV_DIR):
	$(check_valid_edition)
	mkdir -p $@

$(CSV_target): $(STANDARD_CSV) | $(GEN_CSV_DIR)

