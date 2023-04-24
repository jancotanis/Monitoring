require "fileutils"
require 'json'
require 'yaml'
require_relative 'api_base'

module Skykick
	# billing type - term, trial, usage
  TenantData  = Struct.new( :id, :name, :status, :billing_type, :raw_data, :endpoints, :alerts ) do
    def initialize(*)
		super
		self.endpoints ||= {}
		self.alerts ||= []
	end
	
	def is_trial?
		false
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
    def tenants
		if !@tenants
			@tenants = {}
			response = @client.create_connection.get( "/Backup/?$top=250" ) do |req|

			end
			data = JSON.parse( response.body )
			data.each do |item|
				t = TenantData.new( item["id"], item["companyName"], item["orderState"], "", item )
				@tenants[ t.id ] = t
			end
		end
		@tenants.values
    end
    def tenant_by_id( id )
		tenants if !@tenants
		@tenants[ id ]
    end

=begin
[{
 "id": "string",
 "companyName": "string",
 "orderPlacedDate": "2016-01-11T11:01:14Z",
 "onMicrosoftDomain": "string",
 "tenantId": "guid",
 "orderState": "string"
}]
=end

  end
end
