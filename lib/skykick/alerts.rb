require 'json'
require_relative 'api_base'

module Skykick
  AlertData  = Struct.new( :id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :raw_data )

  class Alerts < ApiBase
    def alerts( customer_id )
		@alerts={}
		# Alerts api OData query parameters
		# https://developers.skykick.com/docs/services/012b95c66d31407ba9d56b70731bb5de/operations/84426ef6a9af4ec282a0050b13e6763a
		response = @client.create_connection().get( "/Alerts/#{customer_id}?$top=450" ) do |req|
			authorize_request( req )
		end
		data = JSON.parse( response.body )
		#:id, :description, :severity, :category, :product, :actions
		data.each do |item|
			status = item["Status"]
			if "Active".eql? status
				a = AlertData.new( item["Id"], item["PublishDate"], item["Description"], item["AlertType"], item["Subject"], "Skykick", item["BackupMailboxId"], "Mailbox", item )
				@alerts[ a.id ] = a
			end
		end
		@alerts
    end
=begin
[
   {
      "Id":"430d3865-520b-47ef-99d3-515f6ec33d62",
      "PublishDate":"2021-10-22T18:23:45.243",
      "OrderId":"42ae0179-aa24-483b-a7ce-3a087ad6cca5",
      "Subject":"An Exchange mailbox item was successfully restored",
      "Description":"<p>Alert Code 611: </p>\nThe Exchange mailbox item restore operation completed successfully.",
      "CompanyName":"Mobility Concept B.V.",
      "AlertType":"Success",
      "BackupMailboxId":"e7c91ee0-62f4-48d8-88dd-bba2b11cc0c7",
      "BackupServiceId":"7286ac3a-c9be-4b8a-a06b-8c933dba2e64",
      "BackupSiteId":null,
      "BackupGroupId":null,
      "TemplateId":"3b08e70a-fb95-e411-aadf-6c3be5a8dad0",
      "Status":"AutoArchived"
   },

=end

  end
end
