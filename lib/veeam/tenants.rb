require 'json'
require_relative 'api_base'

module Veeam
  TenantData  = Struct.new( :id, :name, :api, :status, :billing_type, :raw_data, :endpoints, :alerts ) do
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
			#:id, :name, :name, :api, :status, :billing_type, :raw_data, :endpoints, :alerts
			data["data"].each do |item|
				t = TenantData.new( item["instanceUid"], item["name"], nil, item["status"], item["subscriptionPlanUid"], item )
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
      "instanceUid": "0b44edd8-9823-43c0-8708-792108e65958",
      "name": "Machinefabriek Padmos",
      "status": "Active",
      "resellerUid": "445caa74-b8ba-48e6-8277-f2656b581310",
      "subscriptionPlanUid": "774d5c9a-3c63-429b-b3ef-46af208cb98c",
      "permissions": [],
      "isAlarmDetectEnabled": true,
      "_embedded": {
        "organization": null
      }
    },
=end

  end
end
