require "fileutils"
require 'json'
require 'yaml'
require_relative 'api_base'

module Integra365
	# billing type - term, trial, usage
  TenantData  = Struct.new( :id, :name, :raw_data, :endpoints, :alerts ) do
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
    def tenants
		if !@tenants
			@tenants = {}
			response = @client.create_connection.get( "/Api/V1/Tenants" ) do |req|
			end
			data = JSON.parse( response.body )
			data.each do |item|
				# use tennat name as id as this is present in job reporting
				t = TenantData.new( item["tenantName"], item["friendlyName"], item )
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
[
	{
		"id": "gui-id6",
		"vboServerId": "gui-id23",
		"storageSubscriptionModelId": "gui-id",
		"resellerId": "db5d165d-2dfa78e25101",
		"enforcedProfileSettingsId": null,
		"tenantName": "b.onmicrosoft.com",
		"friendlyName": "B",
		"accountingReference": null,
		"customProperties": null
	},
	{
		"id": "gui-id9",
		"vboServerId": "gui-id23",
		"storageSubscriptionModelId": "gui-id",
		"resellerId": "db5d165d-2dfa78e25101",
		"enforcedProfileSettingsId": null,
		"tenantName": "j.onmicrosoft.com",
		"friendlyName": "J Go",
		"accountingReference": null,
		"customProperties": null
	}
]
=end
	end
end
