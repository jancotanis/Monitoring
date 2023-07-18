require 'json'
require_relative 'api_base'

module Zabbix
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

		response = @client.create_connection().post(  ) do |req|
			req.body = JSON.generate( create_request( "host.get", { "groupids":[customer.id], "selectInventory":"extend" } ) )
		end
		data = JSON.parse( response.body )
		#:id, :type, :hostname, :group, :status, :raw_data, :alerts, :incident_alerts 
		data["result"].each do |item|
			ep = EndpointData.new( item["hostid"], "zabbix item", item["name"], customer.id, item["status"], item )
			@endpoints[ ep.id ] = ep
		end

		@endpoints
    end


=begin
status
 0 - (default) monitored host;
 1 - unmonitored host.
maintenance_status
 0 - (default) no maintenance;
 1 - maintenance in effect.
{
   "jsonrpc": "2.0",
   "result": [
	   {
		   "hostid": "10160",
		   "proxy_hostid": "0",
		   "host": "Zabbix server",
		   "status": "0",
		   "lastaccess": "0",
		   "ipmi_authtype": "-1",
		   "ipmi_privilege": "2",
		   "ipmi_username": "",
		   "ipmi_password": "",
		   "maintenanceid": "0",
		   "maintenance_status": "0",
		   "maintenance_type": "0",
		   "maintenance_from": "0",
		   "name": "Zabbix server",
		   "flags": "0",
		   "description": "The Zabbix monitoring server.",
		   "tls_connect": "1",
		   "tls_accept": "1",
		   "tls_issuer": "",
		   "tls_subject": "",
		   "inventory_mode": "1",
		   "active_available": "1"
	   }
   ],
   "id": 1
}
=end

  end
end
