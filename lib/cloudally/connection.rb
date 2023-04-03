require 'json'
require 'faraday'
require 'forwardable'
require 'logger'

module CloudAlly

  class Connection
    extend Forwardable

    def_delegators :@conn, :get, :post
	def_delegators @logger, :info, :error, :fatal, :debug, :warning
    attr_reader :bearer_id, :partner_id, :global_url

	API_URL = 'https://api.cloudally.com'.freeze

    def initialize(client_id, client_secret, user, password, logger=nil)
		@logger = logger
		@client_id = client_id
		@client_secret = client_secret
		@conn = create_connection()
		response = @conn.post('/auth/partner') do |req|
			req.headers['Content-Type'] = 'application/json'
			body = {
			  email: user,
			  password: password
			}
			req.body = body.to_json
		end
		res = JSON.parse( response.body )

		@bearer_id = res[ "accessToken" ]
		raise MissingSessionIdError.new 'Could not find valid session id' if @bearer_id == '' || @bearer_id.nil?
		@conn = create_connection()

	rescue => e
		@logger.error e if @logger
		@logger.error e.response.to_json if @logger
    end


	def create_connection()
      conn = Faraday.new(url: API_URL) do |builder|
        builder.use Faraday::Response::RaiseError
        builder.adapter Faraday.default_adapter
		builder.request :authorization, 'Bearer', @bearer_id if @bearer_id
        builder.headers['client-id'] = @client_id
        builder.headers['client-secret'] = @client_secret
		if @logger
		  builder.response :logger, @logger, { headers: true, bodies: true } do |l|
		    l.filter(/(\"password\"\:\")(.+?)(\".*)/, '\1[REMOVED]\3')
			l.filter(/(client-secret\:)([^&]+)/, '\1[REMOVED]')
			l.filter(/(Authorization\:)([^&]+)/, '\1[REMOVED]')
		  end
		end
      end
	  conn
	end
  end
end
