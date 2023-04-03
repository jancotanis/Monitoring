require "fileutils"
require 'json'
require 'yaml'
require_relative 'api_base'

CACHE_DIR = "./data/"
CACHE_EXT = "-data.yml"

module Sophos
	# billing type - term, trial, usage
  TenantData  = Struct.new( :id, :name, :api, :status, :billing_type, :raw_data, :endpoints, :alerts ) do
    def initialize(*)
		super
		self.endpoints ||= {}
		self.alerts ||= []
	end
	
	def is_trial?
		"trial".eql?( billing_type )
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
			page = 0
			total = 1
			while page < total
				page += 1
				response = @client.connection.get( "/partner/v1/tenants?page=#{page}&pageTotal=true&pageSize=100" ) do |req|
					req.headers['X-Partner-ID'] = @client.connection.partner_id
				end
				data = JSON.parse( response.body )
				data["items"].each do |item|
					t = TenantData.new( item["id"], item["showAs"], item["apiHost"], item["status"], item["billingType"], item )
					@tenants[ t.id ] = t
					endpoints = YAML.load_file( cache_file( t ) ) if File.file?( cache_file( t ) )
					if !endpoints
						puts "loading endpoints"
						endpoints = @client.endpoints( t )
						endpoints ||= {}
						update_cache( t ) 
					end
					t.endpoints = endpoints
				end
				total = data["pages"]["total"]
			end
		end
		@tenants.values
    end
    def tenant_by_id( id )
		tenants if !@tenants
		@tenants[ id ]
    end
private
	def create_cache_dir
		if !Dir.exists?(CACHE_DIR)
			puts "Creating #{CACHE_DIR}..."
			FileUtils::mkdir_p CACHE_DIR
		end
	end
	def cache_file( tenant )
		"#{CACHE_DIR}#{tenant.id}#{CACHE_EXT}"
	end
	def update_cache( tenant )
		create_cache_dir
		File.open( cache_file( tenant ), "w") do |f|
			f.puts( YAML.dump( tenant.endpoints ) )
		end
	end

=begin
items: [{
         "id":"00aa843d-333b-45a2-8617-81386bc35989",
         "showAs":"Overstag Stoffering",
         "name":"Overstag Stoffering",
         "dataGeography":"DE",
         "dataRegion":"eu02",
         "billingType":"usage",
         "partner":{
            "id":"879fd7a8-c0a9-4cb2-b775-583fb604a474"
         },
         "apiHost":"https://api-eu02.central.sophos.com",
         "status":"active"
		}],
   "pages":{
      "current":1,
      "size":50,
      "total":4,
      "items":174,
      "maxSize":100
   }
=end

  end
end
