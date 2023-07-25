require 'json'
require 'yaml'

require_relative 'utils'
require_relative 'SophosAPI'
require_relative 'MonitoringConfig'
require_relative 'MonitoringModel'

SOPHOS = "Sophos"
class SophosIncident < MonitoringIncident
	def initialize( device=nil, start_time=nil, end_time=nil, alert=nil )
		super( SOPHOS, device, start_time, end_time, alert )
	end
end

class EndpointIncident < SophosIncident
	def endpoint_to_s
		alert.property("managedAgent.type")+" "+alert.property("managedAgent.name")
	end
	def to_s
		person = "   User:        #{alert.property('person.name')}\n" if !alert.property('person.name').empty?
		"  #{time_to_s}: #{source} #{alert.severity} alert\n" \
		"   Description: #{alert.description}\n" \
		"   Endpoint:    #{alert.endpoint_type}\n" \
		"#{person}" \
		"   Resolution:  #{alert.property('allowedActions')}" 
	end
end
class ConnectivityIncident < SophosIncident
	def endpoint_to_s
		alert.endpoint_type
	end
	def to_s
		"  #{time_to_s}: #{source} #{alert.severity} alert '#{alert.description}' for #{alert.endpoint_type}"  
	end
end

class SophosMonitor < AbstractMonitor
	attr_reader :config, :all_alerts
	TENANTS_CACHE = SOPHOS.downcase+"-tenants.yml"

	def initialize( report, config, log  ) 
		client = Sophos::Client.new( ENV['SOPHOS_CLIENT_ID'], ENV['SOPHOS_CLIENT_SECRET'], log )
		super( SOPHOS, client, report, config, log )
		@products = {}
		load_tenants
		@config.load_config( source, @tenants )
	end
	
	def run all_alerts
		collect_data()
		@tenants.each do |customer|
			cfg = @config.by_description(customer.description)
			cfg.endpoints = customer.endpoints.count
			if cfg.monitoring?
				all_alerts[customer.id] = customer_alerts = CustomerAlerts.new( customer.description, customer.alerts )
				customer_alerts.customer = customer
				if ( customer.alerts.count > 0 )
					@report.puts "","#{customer.description} - license=#{customer.billing_type}"

					# group alerts by customer
					count = handle_endpoint_alerts( customer_alerts ) if cfg.monitor_endpoints

					# include connectivity issues in case of decive issues
					connection_errors = 0
					if cfg.monitor_connectivity || ( count && count > 0 )
						r = handle_connectivity_alerts( customer_alerts ) 
						connection_errors = r[0]
					end
					customer_alerts.devices.each do |device_id, incidents|
						endpoint = customer.endpoints[device_id]
						@report.puts "- #{endpoint}"
						incidents.each do |type,incident|
							@report.puts incident.to_s
						end
					end
					@report.puts "  connectivity alerts: #{connection_errors}" if connection_errors > 0
				end
			end
		end
		save_tenants
		FileUtil.write_file( FileUtil.daily_file_name(source.downcase+'-alerts.json'), all_alerts.to_json )
		all_alerts
	end
	def handle_unique_alerts( customer, &block )
		# hgash to collect unique alerts
		customer.alerts.values.each do |a|
			block.call customer.devices, a
		end
		customer.devices
	end
	def handle_connectivity_alerts( customer )
		connection_errors = 0
		endpoints = handle_unique_alerts( customer ) do |ep, a|
			if "connectivity".eql?(a.category)
				connection_errors  += 1
				customer.add_incident( a.endpoint_id, a, ConnectivityIncident )
			end
		end
		[connection_errors, endpoints.count]
	end
	def handle_endpoint_alerts( customer )
		endpoints = handle_unique_alerts( customer ) do |ep, a|
			if !"connectivity".eql?( a.category )
				customer.add_incident( a.endpoint_id, a, EndpointIncident )
			end
		end
		endpoints.count
	end

	def load_tenants
		if File.file?( TENANTS_CACHE )
			puts "- loading tenants cache"
			@tenants = YAML.load_file( TENANTS_CACHE ) 
		else
			puts "- loading spohos tenants"
			@tenants = @client.tenants.sort_by{ |t| t.description.upcase }
			save_tenants
		end
	end
	def save_tenants
		FileUtil.write_file( TENANTS_CACHE, YAML.dump( @tenants ) )
	end

	def report_endpoints
		@tenants.each do |customer|
			cfg = @config.by_description(customer.description)

			if cfg.monitoring?
				customer.endpoints.each do |e|
					puts e.to_s
				end
			end
		end
	end
private
	def collect_data
		@tenants.each do |customer|
			customer.clear_endpoint_alerts(  )

			cfg = @config.by_description(customer.description)
			if cfg.monitoring?
				alerts = @client.alerts( customer )
				# add active alerts to customer record
				if ( alerts.count > 0 )
					find_products( alerts )
					customer.alerts = alerts
					alerts.values.each do |a|
						create_endpoint_from_alert( customer, a ) unless customer.endpoints[a.endpoint_id]
						customer.endpoints[a.endpoint_id].alerts << a
					end
				end
			end
			# throuttle sophos api
			sleep( 0.2 )
		rescue => e
			if customer.is_trial?
				puts "","*** Trial customer skipped #{customer.description}"
			else
				@report.puts "","*** Error with #{customer.description}"
				@report.puts e
			end
		end
	end
	def find_products( alerts )
		alerts.values.each do |a|
			@products[ a.product ] = a.product
		end
	end

end
