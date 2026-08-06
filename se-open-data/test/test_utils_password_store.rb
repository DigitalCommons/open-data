require "se_open_data/utils/password_store"
require "minitest/autorun"

# Tests for {SeOpenData::Utils::PasswordStore}.

describe SeOpenData::Utils::PasswordStore do

  # A convenient alias
  PWS = SeOpenData::Utils::PasswordStore

  # Add our stub-bin directory of stub executables to the front
  # of the path, shadowing any real 'pass' command
  ENV['PATH'] = "#{__dir__ + '/stub-bin'}:#{ENV['PATH']}"
  ENV['PASSWORD__SOME_PATH'] = "env sekret"
  ENV['PASSWORD__SOME_PASS'] = "env sekret2"
  
  describe "a default instance" do
    
    pws = PWS.new

    it "use_env_vars? should be false" do
      value(pws.use_env_vars?).must_equal false
    end
    
    it "must assert the presence of an argument" do
      value(proc { pws.get() }).must_raise ArgumentError
    end
    
    it "must get the correct password for a path" do
      value(pws.get('some/path')).must_equal "sekret"
    end
    
    it "must fail if the password is unknown" do
     value(proc { pws.get('some/pass') }).must_raise RuntimeError
    end

  end

  describe "an instance with env enabled" do
    
    pws = PWS.new(use_env_vars: true)

    it "use_env_vars? should be true" do
      value(pws.use_env_vars?).must_equal true
    end
    
    it "must assert the presence of an argument" do
      value(proc { pws.get() }).must_raise ArgumentError
    end
    
    it "must get the correct password, ENV overriding `pass`" do
      value(pws.get('some/path')).must_equal "env sekret"
    end
    
    it "must get the correct password, ENV supplementing `pass`" do
      value(pws.get('some/pass')).must_equal "env sekret2"
    end
    
    it "must get the correct password, fall back to `pass` when not in ENV" do
      value(pws.get('some/other/path')).must_equal "sekret2"
    end
    
    it "must fail if the password is unknown in both `pass` and ENV" do
      value(proc { pws.get('some/other/pass') }).must_raise RuntimeError
    end

    # This is probably Good Enough For Now... but,
    # FIXME deal with misconfiguration situations
    
  end
end

