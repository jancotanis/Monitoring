require 'json'
require_relative 'api_base'

module Sophos
	EndpointData  = Struct.new( :id, :type, :hostname, :group, :status, :raw_data, :alerts, :incident_alerts ) do
    def initialize(*)
        super
        self.alerts ||= []
        self.incident_alerts ||= []
    end
	def clear_alerts
		self.alerts = []
        self.incident_alerts = []
	end
	def to_s
		"#{type} #{hostname}"
	end
  end

  class Endpoints < ApiBase
    def endpoints( customer )
		@endpoints={}
		# pagination ?pageFromKey=<next-key>
=begin
    "pages": {
        "fromKey": "<from-key>",
        "nextKey": "<next-key>",
        "size": 12,
        "maxSize": 50
    }
=end
		response = @client.create_connection( customer.api ).get( "/endpoint/v1/endpoints?pageSize=250" ) do |req|
			req.headers['X-Tenant-ID'] = customer.id
		end
		data = JSON.parse( response.body )
		#:id, :type, :hostname, :group,  :status, :raw_data
		data["items"].each do |item|
			status = item["health"]["overall"] if item["health"]
			ep = EndpointData.new( item["id"], item["type"], item["hostname"], item["groupName"], status, item )
			@endpoints[ ep.id ] = ep
		end
		@endpoints
	rescue => e
		@logger.error e if @logger
		@logger.error e.response.to_json if @logger
    end

=begin
   "items":[
      {
         "id":"00581310-521f-4d70-98b1-ca9128ae79aa",
         "type":"computer",
         "tenant":{
            "id":"f0c4d412-e91c-40fa-b720-f01c91fde12b"
         },
         "hostname":"DAT-PC07",
         "health":{
            "overall":"good",
            "threats":{
               "status":"good"
            },
            "services":{
               "status":"good",
               "serviceDetails":[
                  {
                     "name":"HitmanPro.Alert service",
                     "status":"running"
                  },
                  {
                     "name":"Sophos Endpoint Defense",
                     "status":"running"
                  },
                  {
                     "name":"Sophos Endpoint Defense Service",
                     "status":"running"
                  },
                  {
                     "name":"Sophos File Scanner",
                     "status":"running"
                  },
                  {
                     "name":"Sophos File Scanner Service",
                     "status":"running"
                  },
                  {
                     "name":"Sophos MCS Agent",
                     "status":"running"
                  },
                  {
                     "name":"Sophos MCS Client",
                     "status":"running"
                  },
                  {
                     "name":"Sophos NetFilter",
                     "status":"running"
                  },
                  {
                     "name":"Sophos Network Threat Protection",
                     "status":"running"
                  },
                  {
                     "name":"Sophos System Protection Service",
                     "status":"running"
                  }
               ]
            }
         },
         "os":{
            "isServer":false,
            "platform":"windows",
            "name":"Windows 10 Pro",
            "majorVersion":10,
            "minorVersion":0,
            "build":19045
         },
         "ipv4Addresses":[
            "10.10.120.54"
         ],
         "macAddresses":[
            "A0:8C:FD:DC:1B:D1"
         ],
         "associatedPerson":{
            "name":"DTA\\S.LaGrange",
            "viaLogin":"DTA\\S.LaGrange",
            "id":"adc79069-95f8-45a2-9458-bb52e103868b"
         },
         "tamperProtectionEnabled":false,
         "assignedProducts":[
            {
               "code":"endpointProtection",
               "version":"10.8.11.4",
               "status":"installed"
            },
            {
               "code":"interceptX",
               "version":"2022.1.3.3",
               "status":"installed"
            },
            {
               "code":"coreAgent",
               "version":"2022.4.2.1",
               "status":"installed"
            },
            {
               "code":"xdr",
               "version":"2022.4.2.1",
               "status":"notInstalled"
            }
         ],
         "lastSeenAt":"2023-03-01T06:04:16.007Z",
         "encryption":{
            "volumes":[
               {
                  "volumeId":"\\\\?\\Volume{361a99a0-d915-4efb-9a9a-6910ef750f4f}\\",
                  "status":"notEncrypted"
               }
            ]
         },
         "isolation":{
            "status":"notIsolated",
            "adminIsolated":false,
            "selfIsolated":false
         }
      },

=end

  end
end
