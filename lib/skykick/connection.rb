require 'json'
require 'faraday'
require 'forwardable'
require 'logger'

module Skykick

  class Connection
    extend Forwardable

    def_delegators :@conn, :get, :post
	def_delegators @logger, :info, :error, :fatal, :debug, :warning
    attr_reader :bearer_id, :subscription_id


	API_URL = 'https://apis.skykick.com'.freeze
	# see documentation https://developers.skykick.com/Guides/Authentication
    def initialize(client_id, client_secret, logger=nil)
	  @logger = logger
      @conn = create_connection()
	  @conn.basic_auth(client_id, client_secret)
	  @subscription_id = client_secret
      response = @conn.post('/auth/token') do |req|
		req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
		req.headers['Ocp-Apim-Subscription-Key'] = @subscription_id
		body = {
			grant_type: 'client_credentials',
			scope: 'Partner'
        }
		req.body = URI.encode_www_form( body )
      end
      res = JSON.parse( response.body )

      @bearer_id = res[ "access_token" ]
      raise MissingSessionIdError.new 'Could not find valid session id' if @bearer_id == '' || @bearer_id.nil?
	rescue => e
		@logger.error e if @logger
		@logger.error e.response.to_json if @logger
    end

	def create_connection()
      conn = Faraday.new(url: API_URL) do |builder|
        builder.use Faraday::Response::RaiseError
        builder.adapter Faraday.default_adapter
		builder.request :authorization, 'Bearer', @bearer_id if @bearer_id
        builder.headers['Ocp-Apim-Subscription-Key'] = @subscription_id if @subscription_id
		if @logger
		  builder.response :logger, @logger, { headers: true, bodies: true } do |l|
			# filter header content
			l.filter(/(Authorization\: \"\w+)([^&]+)(\")/, '\1[REMOVED]\3')
			l.filter(/(client-secret\:)([^&]+)/, '\1[REMOVED]')
		    l.filter(/(Ocp-Apim-Subscription-Key\: \")(.+?)(\")/, '\1[REMOVED]\3')
			# filter json content
		    l.filter(/(\"access_token\"\:\")(.+?)(\".*)/, '\1[REMOVED]\3')
		  end
		end
      end
	  conn
	end
	def logout
	end
  end
end
