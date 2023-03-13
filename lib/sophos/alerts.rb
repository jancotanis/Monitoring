require 'json'
require_relative 'api_base'

module Sophos
  AlertData  = Struct.new( :id, :created, :description, :severity, :category, :product, :endpoint_id, :endpoint_type, :raw_data )

  class Alerts < ApiBase
    def alerts( customer )
		@alerts={}
		# https://developer.sophos.com/docs/common-v1/1/routes/alerts/get
		response = @client.create_connection( customer.api ).get( "/common/v1/alerts" ) do |req|
			req.headers['X-Tenant-ID'] = customer.id
		end
		data = JSON.parse( response.body )
		#:id, :description, :severity, :category, :product, :actions
		data["items"].each do |item|
			a = AlertData.new( item["id"], item["raisedAt"], item["description"], item["severity"], item["category"], item["product"], item["managedAgent"]["id"], item["managedAgent"]["type"], item )
			@alerts[ a.id ] = a
		end
		@alerts
    end
=begin
{
  "items": [
    {
      "id": "a5ded91c-6575-435c-a6b4-64b94f9048ff",
      "allowedActions": [
        "acknowledge"
      ],
      "category": "updating",
      "description": "John-PC is out of date.",
      "groupKey": "MSxFdmVudDo6RW5kcG9pbnQ6Ok91dE9mRGF0ZSw1MTMs",
      "managedAgent": {
        "id": "bb90527d-73a8-4e6e-85c6-20c2e0c5bc6f",
        "type": "computer"
      },
      "person": {
        "id": "17dd896f-ee9f-4f7d-a2a2-6a8c0b48ff15"
      },
      "product": "endpoint",
      "raisedAt": "2021-02-12T15:04:53.780Z",
      "severity": "medium",
      "tenant": {
        "id": "79067fa3-e4d0-4769-a5f7-8d6550b3b68b",
        "name": "Acme Corp"
      },
      "type": "Event::Endpoint::OutOfDate"
    },

=end
    def siem( customer )
		@alerts={}
		response = @client.create_connection( customer.api ).get( "/siem/v1/alerts" ) do |req|
			req.headers['X-Tenant-ID'] = customer.id
		end
		data = JSON.parse( response.body )
		#:id, :description, :severity, :category, :product, :actions
		data["items"].each do |item|
			a = AlertData.new( item["id"], item["when"], item["description"], item["severity"], item["category"], item["product"], item["data"]["endpoint_id"], item["data"]["endpoint_type"], item )
			@alerts[ a.id ] = a
		end
		@alerts
    end

=begin
/siem/v1/alerts
{
   "has_more":false,
   "items":[
      {
         "severity":"high",
         "description":"Manual malware cleanup required: 'Mal/Generic-R' at 'C:\\Users\\BUSRA\\Downloads\\Adobe_Photoshop_2021_22.5.9.1101-FP.rar'",
         "data":{
            "core_remedy_items":{
               "totalItems":1,
               "items":[
                  {
                     "result":"FAILED_TO_DELETE",
                     "sophosPid":"",
                     "suspendResult":"NOT_APPLICABLE",
                     "processPath":"",
                     "descriptor":"C:/Users/BUSRA/Downloads/Adobe_Photoshop_2021_22.5.9.1101-FP.rar/Adobe_Photoshop_2021_22.5.9.1101-FP/Adobe_Photoshop_2021_22.5.9.1101/packages/setup.exe",
                     "type":"file"
                  }
               ]
            },
            "created_at":1677579233797,
            "endpoint_id":"cb260020-68b6-4ecf-b680-83fcac004f41",
            "endpoint_java_id":"cb260020-68b6-4ecf-b680-83fcac004f41",
            "endpoint_platform":"windows",
            "endpoint_type":"computer",
            "event_service_id":{
               "type":3,
               "data":"hhtsBp0aS4m2zDY2uH+SRg=="
            },
            "inserted_at":1677579233797,
            "source_app_id":"CORE",
            "source_info":{
               "ip":"192.168.1.158"
            },
            "threat_id":{
               "timestamp":1677579233,
               "date":1677579233000
            },
            "threat_status":"CLEANUP_FAILED",
            "user_match_id":{
               "timestamp":1676904492,
               "date":1676904492000
            },
            "user_match_uuid":{
               "type":3,
               "data":"cAM/OjdIQUi/+tmAreqqqg=="
            }
         },
         "customer_id":"3b9f976c-afc4-428b-8743-3259a4ebbb4c",
         "created_at":"2023-02-28T10:13:53.798Z",
         "threat":"Mal/Generic-R",
         "threat_cleanable":false,
         "event_service_event_id":"861b6c06-9d1a-4b89-b6cc-3636b87f9246",
         "when":"2023-02-28T10:13:49.910Z",
         "location":"BUSRAPC",
         "id":"861b6c06-9d1a-4b89-b6cc-3636b87f9246",
         "type":"Event::Endpoint::CoreCleanFailed",
         "source":"BUSRAPC\\BUSRA"
      }
   ],
   "next_cursor":"MHwyMDIzLTAyLTI4VDE1OjMzOjI2LjMxMlo="
}
=end

  end
end
