require 'json'
require_relative 'api_base'
require_relative 'endpoints.rb'

module CloudAlly
  AlertData  = Struct.new( :id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :raw_data ) do
	def description
		# collect subsources
		failedSubSources = raw_data["backupStatus"].select{ |src| "FAILED".eql? src["status"]}.map{|o| o["subSource"]}.join ' '
		"#{property('entityName')}: #{failedSubSources}"
	end
	def create_endpoint
		CloudAlly::EndpointData.new( endpoint_id, category, endpoint_type )
	end
  end

  class Alerts < ApiBase

	def alerts( tenant=nil )
		@alerts = get_alerts() unless @alerts
		if tenant
			@alerts.values.select{ |a| tenant.eql?( a.property("userId") ) }
		else
			@alerts.values
		end
	end

  private
    def get_alerts()
		@alerts={}
		alert_id = 0
		page = 1
		total = page + 1
		nextPage = ""
		while page <= total
			# https://api.cloudally.com/v3/api-docs/v1
			followingPage = "&page=#{page}&nextPage=#{nextPage}" unless nextPage.empty?

			response = @client.create_connection().get( "/v1/partners/status?pageSize=500#{followingPage}" )
			data = JSON.parse( response.body )

			#:id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :raw_data
			data["data"].each do |item|
				alert_id += 1
				a = create_alert_from_data( alert_id, item )
				@alerts[ alert_id ] = a if a
			end
			page += 1
			total = data["totalPages"].to_i
			nextPage = data["nextPageToken"]
		end
		@alerts
    end
	# filter alerts 
	def create_alert_from_data alert_id, item
		unwanted = ["ACTIVE","ARCHIVED"]
		not_actives = item["backupStatus"].select { |si| !unwanted.include?( si["status"] ) }
		AlertData.new( alert_id, item["lastBackupAttemptDate"], not_actives.first["error"], not_actives.first["status"], item["source"], item["source"], item["taskId"], item["entityName"], item ) if not_actives.count > 0
	end
=begin
{
  "page": 0,
  "totalPages": 0,
  "total": 0,
  "nextPageToken": "string",
  "data": [
    {
      "userId": "string",
      "taskId": "string",
      "source": "GMAIL",
      "entityName": "string",
      "lastBackupDate": "string",
      "lastBackupAttemptDate": "string",
      "backupDuration": 0,
      "size": 0,
      "backupStatus": [
        {
          "subSource": "string",
          "status": "string",
          "error": "string",
          "errFAQLink": "string"
        }
      ]
    }
  ]
}
=end

  end
end
