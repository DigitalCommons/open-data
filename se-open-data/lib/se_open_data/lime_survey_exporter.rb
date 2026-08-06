
require 'se_open_data/lime_survey_rpc'
require 'base64'


module SeOpenData

  # Wrapper for SeOpenData::LimeSurveyRpc that makes exporting responses simpler.
  class LimeSurveyExporter
    # Creates an instance, given the API endpoint and
    # your credentials.
    #
    # This can then be used to export multiple survey response sets.
    #
    # @param url [String] the Lime Survey service URL for your account, e.g.
    # `https://myaccount.limequery.com/index.php/admin/remotecontrol`
    # @param username [String] the user to log in as
    # @param password [String] the user's password
    def initialize(url, username, password)
      @username = username
      @password = password
      @rpc = SeOpenData::LimeSurveyRpc.new(url)
    end


    # Creates an instance, passes it to a block, then {#finalize}s the
    # session.
    #
    # @param (See LimeSurveyExporter#initialize)
    # @yield [LimeSurveyExporter] performs operations in an auto-closed session;
    # {#finalize} is called automatically on return.
    def self.session(*args)

      obj = self.new(*args)
      
      yield(obj)

      return
    ensure
      obj.finalize
    end
    
    # Export a single survey response set.
    #
    # Supplemental options correspond to options following the
    # `survey_id` option described here:
    #
    # https://api.limesurvey.org/classes/remotecontrol_handle.html#method_export_responses
    #
    # @param survey_id [String] the ID for the survey we should export
    # @param options [Hash] options to pass to {SeOpenData::LimeSurveyRpc#export_responses}
    # @return [String] the exported and base-64 decoded data
    def export_responses(survey_id, *options)
      unless @session_key
        @session_key = @rpc.get_session_key(@username, @password)
      end
      data = @rpc.export_responses(@session_key, survey_id, *options)
      if (data.is_a? String)
        return Base64.decode64(data)
      end
      status = data.is_a?(Hash) ? data['status'] : data
      raise RuntimeError.new("Export of survey #{survey_id} failed: #{status}")
    end

    # Releases the session key.
    def finalize
      @rpc.release_session_key(@session_key) if @session_key
      @session_key = nil
    end
  end
end
