require 'json'
require_relative 'api_base'

module Veeam
  AlertData  = Struct.new( :id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :raw_data )

  class Alerts < ApiBase
    def alerts
		@alerts={}
		# https://helpcenter.veeam.com/docs/vac/rest/reference/vspc-rest.html?ver=70#tag/Alarms/operation/GetActiveAlarms
		response = @client.create_connection().get( "/api/v3/alarms/active?limit=250&offset=0" ) 

		data = JSON.parse( response.body )
		#:id, :created, :description, :severity, :category, :product, :actions
		data["data"].each do |item|
			la = item["lastActivation"]
			o = item["object"]
			a = AlertData.new( item["instanceUid"], la["time"], la["message"].strip, la["status"], o["type"], "veeam", o["objectUid"], o["type"], item )
			@alerts[ a.id ] = a
		end
		@alerts
    end
=begin
{
  "data": [
    {
      "instanceUid": "06cd8ec1-f2f4-4156-9614-075fffb21ca1",
      "alarmTemplateUid": "c5b728d2-9c9f-45ed-a127-5baf2af96ec0",
      "repeatCount": 1,
      "object": {
        "instanceUid": "12f787d6-2a97-4ca4-89bf-cad1326d5503",
        "type": "Internal",
        "organizationUid": "12f787d6-2a97-4ca4-89bf-cad1326d5503",
        "locationUid": null,
        "managementAgentUid": null,
        "computerName": "VSPC1",
        "objectUid": "12f787d6-2a97-4ca4-89bf-cad1326d5503",
        "objectName": "VSPC1"
      },
      "lastActivation": {
        "instanceUid": "7c32b0ea-907d-493b-b85e-f5c853b792ac",
        "time": "2023-01-19T04:35:05.4970000+01:00",
        "status": "Info",
        "message": "License auto-update functionality is not enabled.\n\n",
        "remark": "\n\n"
      }
    },
    {
      "instanceUid": "694d5ce8-f72a-4f96-a691-18d11495b3b8",
      "alarmTemplateUid": "917f3b1c-9e81-4cfd-841e-fc07a0097512",
      "repeatCount": 1,
      "object": {
        "instanceUid": "12f787d6-2a97-4ca4-89bf-cad1326d5503",
        "type": "Internal",
        "organizationUid": "12f787d6-2a97-4ca4-89bf-cad1326d5503",
        "locationUid": null,
        "managementAgentUid": null,
        "computerName": "VSPC1",
        "objectUid": "12f787d6-2a97-4ca4-89bf-cad1326d5503",
        "objectName": "VSPC1"
      },
      "lastActivation": {
        "instanceUid": "4501196f-ee2b-45a6-8e75-a08c2f529106",
        "time": "2023-01-19T04:55:06.1030000+01:00",
        "status": "Warning",
        "message": "The same license ID 11112222-1111-2222-3333-111122223333 has been detected for backup servers: VSPC1 (My Company), r2SecondCC (My Company), R2THIRDCC (My Company), R2THIRDVBR (CCTenantThird)\n\n",
        "remark": "\n\n"
      }
    },
    {
      "instanceUid": "f99e9714-d98d-4def-b753-1bc7c714fc95",
      "alarmTemplateUid": "f7388efd-8646-4ec1-9c8b-b049c2410444",
      "repeatCount": 1,
      "object": {
        "instanceUid": "2c99e143-586f-6729-aed4-fb2147ab3e39",
        "type": "BackupAgent",
        "organizationUid": "ada1a61e-caaf-4352-85ef-fae903037163",
        "locationUid": "4293a662-3fa0-4586-b53e-26657c7a6f31",
        "managementAgentUid": "734e931c-7ada-43bd-975d-968556c56b27",
        "computerName": "r2vaw2",
        "objectUid": "6bbf3b42-5585-2ba6-9df2-515b8e62e1ea",
        "objectName": "Windows workstation - Personal files_r2vaw2"
      },
      "lastActivation": {
        "instanceUid": "e1fc6f83-d399-473d-a423-0c6fdf3f2427",
        "time": "2023-01-19T09:45:44.4565372+01:00",
        "status": "Resolved",
        "message": "Job session for \"Windows workstation - Personal files_r2vaw2\" finished with success.\n\n",
        "remark": "\n\n"
      }
    }
  ],
  "meta": {
    "pagingInfo": {
      "total": 3,
      "count": 3,
      "offset": 0
    }
  }
}
=end

  end
end
