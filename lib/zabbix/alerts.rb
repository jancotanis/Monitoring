require 'json'
require_relative 'api_base'
require_relative 'endpoints.rb'

module Zabbix
  AlertData  = Struct.new( :id, :created, :description, :severity_code, :category, :product, :endpoint_id, :endpoint_type, :raw_data, :event ) do
	def create_endpoint
		# :id, :type, :hostname, :group, :status, :raw_data
		Zabbix::EndpointData.new( id, "?", "?" )
	end
	def severity
		severity_text = [ "not classified", "information", "warning", "average", "high", "disaster"]
		if ( severity_code.to_i >= 0 ) && ( severity_code.to_i < severity_text.count )
			severity_text[ severity_code.to_i ]
		else
			severity_code
		end
	end
  end

  class Alerts < ApiBase
    def alerts customer=nil
		@alerts={}
		# https://www.zabbix.com/documentation/current/en/manual/api/reference/problem/get
		response = @client.create_connection().post() do |req|
			query = nil
			query = { "groupids": [customer.id] } if customer
			req.body = JSON.generate( create_request( "problem.get", query ) )
		end

		data = JSON.parse( response.body )
		#:id, :created, :description, :severity_code, :category, :product, :endpoint_id, :endpoint_type, :raw_data, :event
		data["result"].each do |item|
			a = AlertData.new( item["eventid"], zabbix_clock( item["clock"] ), item["name"].strip, item["severity"], item["object"], "zabbix", nil, nil, item )
			event = events_by_id( a.id ).first
			if event["hosts"]
				h = event["hosts"].first
				a.endpoint_id = h["hostid"]
				puts "* host #{a.endpoint_id} in multiple zabbix groups" if event["hosts"].count > 1
			end
			@alerts[ a.id ] = a
		end
		@alerts
    end
=begin
# problem
{
           "jsonrpc": "2.0",
           "result": [
               {
                   "eventid": "1245463",
                   "source": "0",
                   "object": "0",
                   "objectid": "15112",
                   "clock": "1472457242",
                   "ns": "209442442",
                   "r_eventid": "1245468",
                   "r_clock": "1472457285",
                   "r_ns": "125644870",
                   "correlationid": "0",
                   "userid": "1",
                   "name": "Zabbix agent on localhost is unreachable for 5 minutes",
                   "acknowledged": "1",
                   "severity": "3",
                   "cause_eventid": "0",
                   "opdata": "",
                   "suppressed": "1"
               }
           ],
           "id": 1
       }
=end
    def events_by_id id
		id = [id] unless id.is_a? Array
		# https://www.zabbix.com/documentation/current/en/manual/api/reference/event/get
		response = @client.create_connection().post() do |req|
			# "selectRelatedObject":"extend" -> add trigger that generates this event, not interesting at the moment
			req.body = JSON.generate( create_request( "event.get", { "eventids":id, "selectHosts":["hostid"] } ) )
		end

		data = JSON.parse( response.body )
		data["result"]
    end
=begin
{
	"jsonrpc": "2.0",
	"result": [
		{
			"eventid": "112542056",
			"source": "0",
			"object": "0",
			"objectid": "54969",
			"clock": "1683623208",
			"value": "1",
			"acknowledged": "0",
			"ns": "126484783",
			"name": "Stellendam.XGS116 is unavailable by ICMP",
			"severity": "4",
			"r_eventid": "0",
			"c_eventid": "0",
			"correlationid": "0",
			"userid": "0",
			"cause_eventid": "0",
			"opdata": "",
			"hosts": [
				{
					"hostid": "10926"
				}
			],
			"suppressed": "0",
			"urls": []
		}
	],
	"id": 1
}
=end
  end
end
