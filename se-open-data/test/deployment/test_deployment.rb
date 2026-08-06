require_relative "../../lib/load_path"
require "se_open_data/utils/deployment"
require "minitest/autorun"
require "find"
require "fileutils"

run_remote_tests = false

# Tests for {SeOpenData::Utils::Deployment}.
# Quite minimal at the moment...


# Returns a list of the files and directories below path
def contents_of(path)
  Find.find(path).collect do |p|
    p.concat('/') if File.directory? p
    p.delete_prefix(path)
  end
end

describe SeOpenData::Utils::Deployment do
  temp_dir = File.join(__dir__, 'temp')
  
  before do
    @dep = SeOpenData::Utils::Deployment.new
    FileUtils.rm_rf temp_dir
  end
  
  describe "a default instance" do
    it "should perform a local copy" do
      to_dir = File.join(temp_dir, 'dest')
      @dep.deploy(
        from_dir: File.join(__dir__, 'from'),
        to_dir: to_dir,
        exclude: %w(.* *~ *.bak),
      )
      value(contents_of to_dir).must_equal %w(
      /
      /one/
      /one/carrot
      /two/
      /two/apple
      /two/banana  
      )
    end

    it "should perform a remote copy" do # copies to localhost
      skip unless run_remote_tests
      
      to_dir = File.join(File.absolute_path(temp_dir), 'dest')
      @dep.deploy(
        to_server: 'localhost',
        from_dir: File.join(__dir__, 'from'),
        to_dir: to_dir,
        exclude: %w(.* *~ *.bak),
        #verbose: true,
      )
      value(contents_of to_dir).must_equal %w(
      /
      /one/
      /one/carrot
      /two/
      /two/apple
      /two/banana  
      )      
    end
  end
end
