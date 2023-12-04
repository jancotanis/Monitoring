require 'json'
require_relative 'api_base'
require_relative 'endpoints.rb'

module Integra365
  AlertData  = Struct.new( :id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :tenant_id, :raw_data ) do
	def create_endpoint
		# endpoint is backup job
		Integra365::EndpointData.new( id, "BackupJob", self.property( "jobName" ).to_s )
	end
  end

  class Alerts < ApiBase
    def alerts( customer_id=nil )
		# api returns all jobs statuses for all customers so load once
		if !@all_alerts
			@all_alerts = {}

			# https://api.integra-bcs.nl/swagger/index.html
			response = @client.create_connection().get( "/Api/V1/BackupJobReporting" ) do |req|

			end
			data = JSON.parse( response.body )
			data.each do |item|
				# make alerts unique bij adding incident datetime
				id = item["organization"]+":"+item["lastRun"]
				# actual error/warning is under session link for the backup job
				description = item["jobName"] + "\n please check session under backup jobs for a detailed description (https://office365.integra-bcs.nl/backup/index)."
				#:id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :tenant_id, :raw_data
				a = AlertData.new( id, item["lastRun"], description, item["lastStatus"], "Job", "Integra365", id, "BackupJob", item["organization"], item )
				@all_alerts[ a.id ] = a
			end
		end

		@alerts = @all_alerts.select{ |k,a| customer_id.nil? || a.tenant_id.eql?( customer_id )}
    end
=begin
/Api/V1/BackupJobReporting
[
  {
    "organization": "b.onmicrosoft.com",
    "jobName": "B",
    "lastRun": "2023-11-16T13:27:39.757",
    "lastStatus": "Success"
  },
  {

    "lastStatus": "Warning"
  }
]
=end
  end
end
