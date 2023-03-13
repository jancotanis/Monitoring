require 'json'
require_relative 'api_base'

module Veeam
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

  class Endpoints < ApiBase
    def endpoints
		if !@endpoints
			@endpoints=[]
			# pagination ?pageFromKey=<next-key>
			# https://portal.integra-bcs.nl/api/v3/infrastructure/backupServers?limit=100&offset=0
			response = @client.create_connection().get( "/api/v3/infrastructure/backupServers?limit=250&offset=0" ) do |req|
			end
			data = JSON.parse( response.body )
			#:id, :type, :hostname, :group,  :status, :raw_data
			data["data"].each do |item|
				@endpoints << EndpointData.new( item["instanceUid"], item["backupServerRoleType"], item["name"], item["organizationUid"], item["status"], item )
			end
		end
		@endpoints
	rescue => e
		@logger.error e if @logger
		@logger.error e.response.to_json if @logger
    end

=begin
{
  "meta": {
    "pagingInfo": {
      "total": 28,
      "count": 28,
      "offset": 0
    }
  },
  "data": [
    {
      "instanceUid": "35b81455-b7f2-49b6-93ca-d1c52616eb95",
      "name": "HYPERV1",
      "organizationUid": "e46f868f-a078-460a-82e5-70c050956b84",
      "locationUid": "598576d7-2de0-4287-96dd-088b78eac6a6",
      "managementAgentUid": "b266d868-060a-44d9-8094-281b49cc42a2",
      "version": "11.0.0.837",
      "displayVersion": "11.0.0.837 P20210525",
      "installationUid": "955544d4-ca72-4882-b0c1-159889d9cbf7",
      "backupServerRoleType": "Client",
      "status": "Healthy"
    },
=end

  end
end
