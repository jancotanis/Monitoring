require 'json'
require_relative 'api_base'

module Veeam
  TenantData  = Struct.new( :id, :name, :status, :billing_type, :raw_data, :endpoints, :alerts ) do
    def initialize(*)
		super
		self.endpoints ||= {}
		self.alerts ||= []
	end
	
	def description
		# it looks like new tenants are created as COAS Business Systems and showAs is the actual name.
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
			# https://portal.integra-bcs.nl/api/swagger/index.html
			response = @client.create_connection().get( "/api/v3/organizations/companies?limit=100&offset=0" ) 
			data = JSON.parse( response.body )
			#:id, :name, :status, :billing_type, :raw_data, :endpoints, :alerts
			data["data"].each do |item|
				t = TenantData.new( item["instanceUid"], item["name"], item["status"], item["subscriptionPlanUid"], item )
				@tenants[ t.id ] = t
			end
=begin
			endpoints = @client.endpoints
			endpoints.each do |ep|
				@tenants[ep.tenant].endpoints[ep.id] = ep
			end
=end
		end
		@tenants.values
    end
=begin
{
  "meta": {
    "pagingInfo": {
      "total": 30,
      "count": 30,
      "offset": 0
    }
  },
  "data": [
    {
      "instanceUid": "0b454dd8-69823-463c0-86708-792465108e65958",
      "name": "Company name",
      "status": "Active",
      "resellerUid": "423545caa74-9b8ba-498e6-82977-f296563b565781310",
      "subscriptionPlanUid": "772ga4d5c9a-3c36-4239-b33e-46adffaf208cb98c",
      "permissions": [],
      "isAlarmDetectEnabled": true,
      "_embedded": {
        "organization": null
      }
    },
=end

  end
end
