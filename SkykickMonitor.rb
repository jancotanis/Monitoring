require "dotenv"
require 'json'

require_relative 'utils'
require_relative 'SkykickAPI'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'
require_relative 'lib/skykick/endpoints'


class BackupIncident < MonitoringIncident
	def source
		"Skykick"
	end
	def endpoint_to_s
		"#{alert.endpoint_type} #{alert.endpoint_id}"
	end
	def to_s
		"  #{time_to_s}: #{alert.severity} alert\n" \
		"   Description: #{alert.description}\n"
	end
end

class SkykickMonitor
	attr_reader :config, :all_alerts
	TENANTS_CACHE = "skykick-tenants.yml"

	def initialize( report, config, log  ) 
		@all_alerts = {}
		@report = report
		@client = Skykick::Client.new( ENV['SKYKICK_CLIENT_ID'], ENV['SKYKICK_CLIENT_SECRET'], log )

		@tenants = @client.tenants.sort_by{ |t| t.description.upcase }

		@config = config
		@config.load_config( "Skykick", @tenants )
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
									customer_alerts.add_incident( a.endpoint_id, a, BackupIncident )
									@report.puts "  #{a.created} #{a.severity} #{a.description} "
								end
							end
						end
					end
				end
			end
		end

		FileUtil.write_file( FileUtil.daily_file_name('skykick-alerts.json'), all_alerts.to_json )
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
						if !a.severity.eql? "Information"
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
		result = @client.alerts( tenant.id )
		# resturn hash of alerts
		result
	end
	def create_endpoint_from_alert( customer, alert )
		device_id = alert.endpoint_id
		endpoint = customer.endpoints[device_id]
		if !endpoint
			# create endpoint from alert, assume mailbox is the endpoint
			type = "?"
			name = "?"
			if alert
				type = "BackupService"
				name = alert.property( "BackupMailboxId" ).to_s
			end
			customer.endpoints[device_id] = endpoint = Skykick::EndpointData.new( device_id, type, name )
		end
		endpoint
	end

end
