require 'json'
require 'yaml'

require_relative 'utils'
require_relative 'ZabbixAPI'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

ZABBIX = "Zabbix"
Z_MINIMUM_SEVERITY = "3" #average
class ZabbixIncident < MonitoringIncident
	def initialize( device=nil, start_time=nil, end_time=nil, alert=nil )
		super( ZABBIX, device, start_time, end_time, alert )
	end
	def endpoint_to_s
		device.to_s
	end
	def to_s
		"  #{time_to_s}: #{source} #{alert.severity} alert\n" \
		"   Description: #{alert.description}\n"
	end
end

class ZabbixMonitor < AbstractMonitor
	attr_reader :config, :all_alerts, :tenants

	def initialize( report, config, log  ) 
		client = Zabbix::ClientWrapper.new( ENV['ZABBIX_API_HOST'], ENV['ZABBIX_API_KEY'], log )
		super( ZABBIX, client, report, config, log )
		@tenants = @client.tenants.sort_by{ |t| t.description.upcase }
		@config.load_config( source, @tenants )
	end

	def run all_alerts
		collect_data()
		@tenants.each do |customer|
			cfg = @config.by_description(customer.description)
      if cfg.monitor_connectivity
        cfg.endpoints = customer.endpoints.count if customer.endpoints.count > 0
				all_alerts[customer.id] = customer_alerts = CustomerAlerts.new( customer.description, customer.alerts )
				customer_alerts.customer = customer
				if ( customer.alerts.count > 0 )
					@report.puts "", customer.description

					customer.endpoints.values.each do |ep|
						if ep.alerts.count > 0
							@report.puts "- Endpount #{ep}"
							ep.alerts.each do |a|
								# group alerts by customer
								if a.severity_code >= Z_MINIMUM_SEVERITY
									customer_alerts.add_incident( ep, a, ZabbixIncident )
									@report.puts "  #{a.created} #{a.severity} #{a.description} "
								end
							end
						end
					end
				end
			end
		end
		FileUtil.write_file( FileUtil.daily_file_name(source.downcase+'-alerts.json'), all_alerts.to_json )
		all_alerts
	end
private
	def collect_data
		@tenants.each do |customer|
			customer.clear_endpoint_alerts()

			cfg = @config.by_description(customer.description)
			if cfg.monitor_endpoints
				alerts = @client.alerts( customer )
				# add active alerts to customer record
				if ( alerts.count > 0 )
					customer.alerts = alerts
					alerts.values.each do |a|
						create_endpoint_from_alert( customer, a ) unless customer.endpoints[a.endpoint_id]
						customer.endpoints[a.endpoint_id].alerts << a
					end
				end
			end
		rescue => e
			@report.puts "","*** Error with #{customer.description}"
			@report.puts e
		end
	end

end
