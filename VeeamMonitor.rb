require "dotenv"
require 'json'

require_relative 'utils'
require_relative 'VeeamAPI'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

VEEAM = "Veeam"

class VeeamBackupIncident < MonitoringIncident
	def initialize( device=nil, start_time=nil, end_time=nil, alert=nil )
		super( VEEAM, device, start_time, end_time, alert )
	end
	def endpoint_to_s
		alert.property("object.type")+" "+alert.property("object.computerName")+" "+alert.property("object.objectName")
	end
end

class VeeamMonitor < AbstractMonitor
	attr_reader :config, :all_alerts

	def initialize( report, config, log ) 
		client = Veeam::ClientWrapper.new( ENV['VEEAM_API_HOST'], ENV['VEEAM_API_KEY'], log )
		super( VEEAM, client, report, config, log )

		@alerts = @client.alerts
		@tenants = @client.tenants.sort_by{ |t| t.description.upcase }

		@config.load_config( source, @tenants )
	end
	
	def run all_alerts
		collect_data()
		@tenants.each do |customer|
			cfg = @config.by_description(customer.description)
			if cfg.monitor_backup
				all_alerts[customer.id] = customer_alerts = CustomerAlerts.new( customer.description, customer.alerts )
				customer_alerts.customer = customer
				if ( customer.alerts.count > 0 )
					@report.puts "",customer.description
					# walk through all endpoint elerts
					customer.endpoints.values.each do |ep|
						if ep.alerts.count > 0
							@report.puts "- Endpount #{ep}"
							ep.alerts.each do |a|
								# group alerts by customer
								if !a.severity.eql? "Resolved"
									customer_alerts.add_incident( a.endpoint_id, a, VeeamBackupIncident )
									@report.puts "  #{a.created} #{a.severity} #{a.description} "
								end
							end
						end
					end
				end
			end
		end
		FileUtil.write_file( FileUtil.daily_file_name(source.downcase+'-alerts.json'), @alerts.to_json )
		all_alerts
	end

private
	def collect_data
		@tenants.each do |customer|
			customer.clear_endpoint_alerts(  )
			cfg = @config.by_description(customer.description)
			if cfg.monitor_backup
				customer_alerts = collect_alerts( customer )
				# add active alerts to customer record
				if ( customer_alerts.count > 0 )
					customer.alerts = customer_alerts
					customer_alerts.values.each do |a|
						if !a.severity.eql? "Resolved"
							create_endpoint_from_alert( customer, a ) unless customer.endpoints[a.endpoint_id]
							customer.endpoints[a.endpoint_id].alerts << a if customer.endpoints[a.endpoint_id]
						end
					end
				end
			end
			# throuttle api
			sleep( 0.05 )
		end
	end
	def collect_alerts tenant
		ca = @alerts.values.select{ |a| tenant.id.eql?( a.property("object.organizationUid") ) }
		result = {}
		ca.each do |a|
			result[a.id] = a
		end
		result
	end

end
