require 'json'
require_relative 'api_base'

module CloudAlly
	EndpointData  = Struct.new( :id, :type, :hostname, :tenant, :status, :raw_data, :alerts, :incident_alerts ) do
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

  # abstraction for backup tasks, eacht customer has number of tasks to run (or endpoints)
  class Endpoints < ApiBase
	def endpoints( tenant )
		@endpoints = get_endpoints() unless @endpoints
		@endpoints.values.select { |e| tenant.eql?( e.tenant ) }
	end
    def get_endpoints()
		@endpoints={}
		items = 0
		page = 1
		total = page + 1
		nextPage = ""
		while page <= total
			# https://api.cloudally.com/v3/api-docs/v1
			followingPage = "&page=#{page}&nextPage=#{nextPage}" unless nextPage.empty?

			response = @client.create_connection().get( "/v1/partners/tasks?pageSize=500#{followingPage}" )
			data = JSON.parse( response.body )

			#:id, :type, :hostname, :tenant, :status, :raw_data, :alerts, :incident_alerts
			data["data"].each do |item|
				items += 1
				@endpoints[ item["id"] ] = EndpointData.new( item["id"], item['type'] +"/"+ item['source'], item['alias'], item['userId'], item['status'], item )
			end
			page += 1
			total = data["totalPages"].to_i
			nextPage = data["nextPageToken"]
		end
		@endpoints
    end
    
=begin
{
	"page": 1,
	"totalPages": 1,
	"total": 109,
	"nextPageToken": null,
	"data": [
		{
			"id": "fe1dsea5-b876d-46680-94ae-2f6383dsfg",
			"account": "i@s.tld",
			"type": "BACKUP",
			"source": "SHAREPOINT_MULTI",
			"userId": "8abcd163a8-4973-4b6a-9e54-ea63594kfca",
			"domain": null,
			"status": "ACTIVE",
			"region": "EU_F",
			"alias": "S-Office365-Sharepoint",
			"backupTaskId": null,
			"index": true,
			"snapshotDate": null,
			"lastBackupDates": {
				"SHAREPOINT_MULTI": 202303345630202812
			},
			"nextBackup": "In 21 hours",
			"progress": null,
			"size": 7355928,
			"createDate": "2021-01-07T11:44:57.000Z",
			"numOfBilledEntities": 5,
			"numOfEntities": 5,
			"userEmail": "i@s.tld",
			"multiEntitiesTask": true
		},
=end

  end
end
