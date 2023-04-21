require "dotenv"
require 'json'

require_relative 'utils'
require_relative 'CloudAllyAPI'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

CLOUDALLY = "CloudAlly"
class CloudBackupIncident < MonitoringIncident
	def initialize( device=nil, start_time=nil, end_time=nil, alert=nil )
		super( CLOUDALLY, device, start_time, end_time, alert )
	end
#	def source
#		"CloudAlly"
#	end
	def endpoint_to_s
		"#{alert.endpoint_type}"
	end
end

class CloudAllyMonitor
	attr_reader :config, :all_alerts

	def initialize( report, config, log ) 
		@all_alerts = {}
		@report = report
		@client = CloudAlly::Client.new( 
			ENV["CLOUDALLY_CLIENT_ID"],
			ENV["CLOUDALLY_CLIENT_SECRET"],
			ENV["CLOUDALLY_USER"],
			ENV["CLOUDALLY_PASSWORD"],
			log			
		)

		@tenants = @client.tenants.sort_by{ |t| t.description.upcase }

		@config = config
		@config.load_config( CLOUDALLY, @tenants )
	end
	
	def run all_alerts
		collect_data()
		@tenants.each do |customer|
			cfg = @config.by_description(customer.description)
			if true || cfg.monitor_backup
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

		FileUtil.write_file( FileUtil.daily_file_name(CLOUDALLY.downcase+'-alerts.json'), all_alerts.to_json )
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
			if true || cfg.monitor_backup
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
			customer.endpoints[device_id] = endpoint = CloudAlly::EndpointData.new( device_id, a.category, a.endpoint_type )
		end
		endpoint
	end
end
