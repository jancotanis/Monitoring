require 'dotenv'
require 'json'
require 'cloudally'

require_relative 'CloudAllyAPI'
require_relative 'utils'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

CLOUDALLY = "CloudAlly"
class CloudBackupIncident < MonitoringIncident
	def initialize( device=nil, start_time=nil, end_time=nil, alert=nil )
		super( CLOUDALLY, device, start_time, end_time, alert )
	end
	def endpoint_to_s
		"#{alert.endpoint_type}"
	end
end

class CloudAllyMonitor < AbstractMonitor
	attr_reader :config, :all_alerts

	def initialize( report, config, log ) 
		client = CloudAlly::ClientWrapper.new( 
			ENV["CLOUDALLY_CLIENT_ID"],
			ENV["CLOUDALLY_CLIENT_SECRET"],
			ENV["CLOUDALLY_USER"],
			ENV["CLOUDALLY_PASSWORD"],
			log
		)
		super( CLOUDALLY, client, report, config, log )

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
									customer_alerts.add_incident( a.endpoint_id, a, CloudBackupIncident )
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
			# add endpoints to customer
			endpts = @client.endpoints( customer.id )
			endpts.each do |e|
				customer.endpoints[e.id] = e
			end

			cfg = @config.by_description(customer.description)
			if cfg.monitor_backup
				customer_alerts = collect_alerts( customer )
				# add active alerts to customer record
				if ( customer_alerts.count > 0 )
					customer.alerts = customer_alerts
					customer_alerts.each do |a|
						if a.severity.eql? "FAILED"
							create_endpoint_from_alert( customer, a ) unless customer.endpoints[a.endpoint_id]
							customer.endpoints[a.endpoint_id].alerts << a if customer.endpoints[a.endpoint_id]
						end
					end
				end
			end
		end
	end
end
