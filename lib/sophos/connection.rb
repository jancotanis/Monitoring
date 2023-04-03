require 'json'
require 'faraday'
require 'forwardable'
require 'logger'

module Sophos

  class Connection
    extend Forwardable

    def_delegators :@conn, :get, :post
	def_delegators @logger, :info, :error, :fatal, :debug, :warning
    attr_reader :bearer_id, :partner_id, :global_url

    ID_URL = 'https://id.sophos.com'.freeze
	API_URL = 'https://api.central.sophos.com'.freeze

    def initialize(client_id, client_secret, logger=nil)
	  @logger = logger
      @conn = create_connection( ID_URL )

      response = @conn.post('/api/v2/oauth2/token') do |req|
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        body = {
		  grant_type: 'client_credentials',
          client_id: client_id,
          client_secret: client_secret,
		  scope: 'token'
        }
		req.body = URI.encode_www_form( body )
      end
      res = JSON.parse( response.body )

      @bearer_id = res[ "access_token" ]
      raise MissingSessionIdError.new 'Could not find valid session id' if @bearer_id == '' || @bearer_id.nil?
	  @conn = create_connection( API_URL )
	  set_whoami
	rescue => e
		@logger.error e if @logger
		@logger.error e.response.to_json if @logger
    end

	def set_whoami
	  res = JSON.parse( self.get( "/whoami/v1" ).body )
	  @partner_id = res["id"]
	  @global_url = res["apiHosts"]["global"]
	end

	def create_connection( url )
      conn = Faraday.new(url: url) do |builder|
        builder.use Faraday::Response::RaiseError
        builder.adapter Faraday.default_adapter
		builder.request :authorization, 'Bearer', @bearer_id if @bearer_id
		if @logger
		  builder.response :logger, @logger, { headers: true, bodies: true } do |l|
			# filter www encoded content
		    l.filter(/(client_secret\=)(.+?)(\&)/, '\1[REMOVED]\3')
			# filter header content
			l.filter(/(Authorization\: \"\w+)([^&]+)(\")/, '\1[REMOVED]\3')
			# filter json content
		    l.filter(/(\"access_token\"\: \")(.+?)(\".*)/, '\1[REMOVED]\3')
		  end
		end
      end
	  conn
	end
	def logout
	end
  end
end
