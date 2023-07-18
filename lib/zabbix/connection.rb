require 'json'
require 'faraday'
require 'forwardable'
require 'logger'

module Zabbix

  class Connection
    extend Forwardable

    def_delegators :@conn, :get, :post
	def_delegators @logger, :info, :error, :fatal, :debug, :warning
    attr_reader :bearer_id, :global_url

    def initialize(global_url, api_key, logger=nil)
		@logger = logger
		@global_url = global_url + "/zabbix/api_jsonrpc.php"
		@bearer_id = api_key
		raise MissingSessionIdError.new 'Could not find valid session id' if @bearer_id == '' || @bearer_id.nil?

	rescue => e
		@logger.error e if @logger
		@logger.error e.response.to_json if @logger
    end

	def create_connection()
	  headers = { "Content-Type" => "application/json-rpc" }
      conn = Faraday.new(url: @global_url, headers: headers) do |builder|
        builder.use Faraday::Response::RaiseError
        builder.adapter Faraday.default_adapter
		builder.request :authorization, 'Bearer', @bearer_id if @bearer_id

		if @logger
		  builder.response :logger, @logger, { headers: true, bodies: true } do |l|
			# filter header content
			l.filter(/(Authorization\: \"\w+)([^&]+)(\")/, '\1[REMOVED]\3')
		  end
		end
      end
	  conn
	end
	def logout
	end
  end
end
