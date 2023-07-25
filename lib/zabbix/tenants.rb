require 'json'
require_relative 'api_base'

module Zabbix

  TenantData  = Struct.new( :id, :name, :status, :raw_data, :endpoints, :alerts ) do
    def initialize(*)
		super
		self.endpoints ||= {}
		self.alerts ||= []
	end
	
	def description
		name
	end

	def clear_endpoint_alerts
		if self.endpoints
			endpoints.each do |k,v|
				v.clear_alerts
			end
		end
	end
  end

  class Tenants < ApiBase
	# one zabbix group per customer/tenant
	def tenants
		if !@tenants
			@tenants = {}
			response = @client.create_connection().post() do |req|
				req.body = JSON.generate( create_request( "hostgroup.get" ) )
			end
			data = JSON.parse( response.body )

			data["result"].each do |item|
				t = TenantData.new( item["groupid"], item["name"], nil, item )
				@tenants[ t.id ] = t
				endpoints = @client.endpoints( t )
				endpoints ||= {}
				t.endpoints = endpoints
			end
		end
		@tenants.values
	end
=begin
{
	"jsonrpc": "2.0",
	"result": [
		{
			"groupid": "2",
			"name": "Linux servers",
			"internal": "0"
		},
		{
			"groupid": "4",
			"name": "Zabbix servers",
			"internal": "0"
		}
	],
	"id": 1
}
=end

  end
end
