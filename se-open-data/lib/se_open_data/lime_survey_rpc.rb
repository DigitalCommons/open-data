
require 'net/http'
require 'net/https'
require 'uri'
require 'json'


module SeOpenData
  
  # Class to access Lime Survey's JSON-RPC API, "RemoteControl 2"
  # See https://manual.limesurvey.org/RemoteControl_2_API
  #
  # In its current form it's fairly low-level, essentially it's just a
  # JSON RPC client, with no built-in knowledge of the API itself. You
  # need to know how to use the API, and possibly perform extra
  # conversions on the returned data. See the API docuentation linked
  # above.
  #
  # To use this, you need log-in credentials, and you must enable the
  # API in RPCJSON mode, by logging in to the LimeSurvey
  # administration, going to "Global settings", choosing the tab
  # "Interfaces" and selecting the JSON-RPC service.
  #
  # Adapted from this example:
  # https://en.bitcoin.it/wiki/API_reference_(JSON-RPC)#Ruby
  class LimeSurveyRpc
    # Initialise an instance, given the API endpoint.
    #
    # @param url [String] the Lime Survey service URL for your account, e.g.
    # `https://myaccount.limequery.com/index.php/admin/remotecontrol`
    def initialize(service_url)
      @uri = URI.parse(service_url)
    end

    # Dynamically implements the API by mapping method calls to
    # RPC calls.
    # @raise JSONRPCError if there is an API error returned
    def method_missing(name, *args)
      post_body = { 'method' => name, 'params' => args, 'id' => 'jsonrpc' }.to_json
      resp = JSON.parse( http_post_request(post_body) )
      raise JSONRPCError, resp['error'] if resp['error']
      resp['result']
    end

    # Posts a request to the API
    # @param post_body [String] the content to post
    # @return the response body
    # @raise JSONRPCError if the post does not get a success response
    def http_post_request(post_body)
      http    = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = @uri.scheme == 'https'
      request = Net::HTTP::Post.new(@uri.request_uri)
      request.basic_auth @uri.user, @uri.password
      request.content_type = 'application/json'
      request.body = post_body
      response = http.request(request)
      if response.kind_of?(Net::HTTPSuccess)
        return response.body
      end

      raise JSONRPCError.new("request to #{@uri.request_uri} failed: #{response.msg}")
    end

    # An exception thrown if there is an API error
    class JSONRPCError < RuntimeError; end
  end
end
