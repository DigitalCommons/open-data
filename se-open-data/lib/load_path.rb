# This file is a convenience, allowing scripts to set the necessary
# $LOAD_PATH to require files from this directory, like this:
#
# require_relative '../lib/load_path'
# require 'se_open_data/some/file1'
# require 'se_open_data/some/file2'
# ...

$LOAD_PATH.unshift(File.absolute_path(__dir__))
