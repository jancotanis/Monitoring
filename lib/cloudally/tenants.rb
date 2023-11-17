require "fileutils"
require 'json'
require 'yaml'
require_relative 'api_base'

module CloudAlly
	# billing type - term, trial, usage
  TenantData  = Struct.new( :id, :name, :status, :billing_type, :raw_data, :endpoints, :alerts ) do
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
			response = @client.create_connection.get( "/v1/partners/users?pageSize=500&page=1" ) do |req|
			end
			data = JSON.parse( response.body )
			data["data"].each do |item|
				t = TenantData.new( item["id"], item["name"], item["status"], item["discount"].to_s, item )
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
{
   "page":1,
   "totalPages":1,
   "total":38,
   "nextPageToken":null,
   "data":[
      {
         "id":"4fbd097f-77e4-4641-af891-ec7sftw099ee",
         "name":"B",
         "email":"w@b.tld",
         "status":"ACTIVE",
         "date":20210311,
         "dailyReport":true,
         "region":"EU_F",
         "discount":35,
         "reportEmails":[
            
         ],
         "partnerID":"RASD1234",
         "currency":"EUR",
         "customStorage":null,
         "ms365EnterprisePlan":true,
         "gsuiteEnterprisePlan":true
      },
=end
	end
end
